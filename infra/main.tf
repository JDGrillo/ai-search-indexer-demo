
terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "azurerm" {
  features {
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
  storage_use_azuread = true
  subscription_id     = var.subscription_id
}

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  suffix                        = random_string.suffix.result
  storage_account_name          = "st${var.project_name_short}${local.suffix}"
  function_storage_account_name = "st${var.project_name_short}fn${local.suffix}"
  search_service_name           = "srch-${var.project_name}-${local.suffix}"
  cognitive_account_name        = "ai-${var.project_name}-${local.suffix}"
  function_app_name             = "func-${var.project_name}-${local.suffix}"
  backend_app_name              = "app-${var.project_name}-backend-${local.suffix}"
  frontend_app_name             = "app-${var.project_name}-frontend-${local.suffix}"
}

# ─── Resource Group ─────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ─── Storage Account (for PDF documents) ────────────────────────────────────────
resource "azurerm_storage_account" "docs" {
  name                            = local.storage_account_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "documents" {
  name                  = var.storage_container_name
  storage_account_id    = azurerm_storage_account.docs.id
  container_access_type = "private"
}

# ─── Azure AI Search ────────────────────────────────────────────────────────────
resource "azurerm_search_service" "main" {
  name                         = local.search_service_name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  sku                          = "standard"
  local_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ─── Azure AI Services (Foundry — hosts OpenAI models) ─────────────────────────
resource "azurerm_cognitive_account" "openai" {
  name                  = local.cognitive_account_name
  resource_group_name   = azurerm_resource_group.main.name
  location              = azurerm_resource_group.main.location
  kind                  = "AIServices"
  sku_name              = "S0"
  custom_subdomain_name = local.cognitive_account_name
  local_auth_enabled    = false

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ─── GPT-4o Model Deployment ────────────────────────────────────────────────────
resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-11-20"
  }

  sku {
    name     = "GlobalStandard"
    capacity = 10
  }
}

# ─── User-Assigned Managed Identity (for backend application) ───────────────────
resource "azurerm_user_assigned_identity" "backend" {
  name                = "${var.project_name}-backend-mi"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

# ─── Log Analytics + Application Insights ────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project_name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# RBAC Role Assignments
# ═══════════════════════════════════════════════════════════════════════════════

# --- AI Search system MI → Storage Blob Data Reader (indexer reads blobs) ------
resource "azurerm_role_assignment" "search_to_storage" {
  scope                = azurerm_storage_account.docs.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_search_service.main.identity[0].principal_id
}

# --- Backend MI → Search Index Data Reader (query the index) -------------------
resource "azurerm_role_assignment" "backend_search_reader" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = azurerm_user_assigned_identity.backend.principal_id
}

# --- Backend MI → Search Service Contributor (manage indexer) ------------------
resource "azurerm_role_assignment" "backend_search_contributor" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azurerm_user_assigned_identity.backend.principal_id
}

# --- Backend MI → Cognitive Services OpenAI User (call OpenAI API) -------------
resource "azurerm_role_assignment" "backend_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.backend.principal_id
}

# --- Deployer (current user) → roles for setup scripts & local development -----
resource "azurerm_role_assignment" "deployer_storage_contributor" {
  scope                = azurerm_storage_account.docs.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_search_contributor" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Service Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_search_reader" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ═══════════════════════════════════════════════════════════════════════════════
# Networking — VNet, Private Endpoints, DNS
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

# --- NAT Gateway (outbound internet for VNet-integrated apps) ------------------
resource "azurerm_public_ip" "nat" {
  name                = "${var.project_name}-nat-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "main" {
  name                = "${var.project_name}-natgw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "function" {
  subnet_id      = azurerm_subnet.function.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "appservice" {
  subnet_id      = azurerm_subnet.appservice.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet" "function" {
  name                            = "snet-function"
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = ["10.0.1.0/24"]
  default_outbound_access_enabled = false

  delegation {
    name = "function-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "appservice" {
  name                            = "snet-appservice"
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = ["10.0.3.0/24"]
  default_outbound_access_enabled = false
  service_endpoints               = ["Microsoft.Web"]

  delegation {
    name = "appservice-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                            = "snet-pe"
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = ["10.0.2.0/24"]
  default_outbound_access_enabled = false
}

# --- Private DNS zone for blob storage -----------------------------------------
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "blob-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

# --- Private endpoint for document storage (blob) ------------------------------
resource "azurerm_private_endpoint" "storage_blob" {
  name                = "${var.project_name}-pe-blob"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "blob-connection"
    private_connection_resource_id = azurerm_storage_account.docs.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  tags = var.tags
}

# --- Private endpoint for function runtime storage (blob) ----------------------
resource "azurerm_private_endpoint" "function_storage_blob" {
  name                = "${var.project_name}-pe-func-blob"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "func-blob-connection"
    private_connection_resource_id = azurerm_storage_account.function.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  tags = var.tags
}

# --- Private DNS zones for queue and table (function runtime) ------------------
resource "azurerm_private_dns_zone" "queue" {
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "queue" {
  name                  = "queue-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.queue.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

resource "azurerm_private_dns_zone" "table" {
  name                = "privatelink.table.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "table" {
  name                  = "table-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.table.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

# --- Private endpoints for function storage (queue + table) --------------------
resource "azurerm_private_endpoint" "function_storage_queue" {
  name                = "${var.project_name}-pe-func-queue"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "func-queue-connection"
    private_connection_resource_id = azurerm_storage_account.function.id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "queue-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.queue.id]
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "function_storage_table" {
  name                = "${var.project_name}-pe-func-table"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "func-table-connection"
    private_connection_resource_id = azurerm_storage_account.function.id
    subresource_names              = ["table"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "table-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.table.id]
  }

  tags = var.tags
}

# --- Shared private link: AI Search → Storage (indexer access) -----------------
resource "azurerm_search_shared_private_link_service" "storage" {
  name               = "blob-shared-pl"
  search_service_id  = azurerm_search_service.main.id
  subresource_name   = "blob"
  target_resource_id = azurerm_storage_account.docs.id
  request_message    = "Search indexer access to document storage"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Azure Function App (document management)
# ═══════════════════════════════════════════════════════════════════════════════

# --- User-Assigned Managed Identity (for function app) -------------------------
resource "azurerm_user_assigned_identity" "function" {
  name                = "${var.project_name}-function-mi"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

# Separate storage account for Function App runtime
resource "azurerm_storage_account" "function" {
  name                            = local.function_storage_account_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  tags = var.tags
}

# --- Function MI → roles on runtime storage (BEFORE function app creation) -----
resource "azurerm_role_assignment" "function_runtime_blob" {
  scope                = azurerm_storage_account.function.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.function.principal_id
}

resource "azurerm_role_assignment" "function_runtime_account" {
  scope                = azurerm_storage_account.function.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.function.principal_id
}

resource "azurerm_role_assignment" "function_runtime_queue" {
  scope                = azurerm_storage_account.function.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.function.principal_id
}

resource "azurerm_role_assignment" "function_runtime_table" {
  scope                = azurerm_storage_account.function.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.function.principal_id
}

# --- Function MI → Storage Blob Data Contributor on doc storage ----------------
resource "azurerm_role_assignment" "function_storage" {
  scope                = azurerm_storage_account.docs.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.function.principal_id
}

# --- RBAC propagation delay (Azure AD can take up to 60s) ----------------------
resource "time_sleep" "function_rbac_propagation" {
  create_duration = "60s"

  depends_on = [
    azurerm_role_assignment.function_runtime_blob,
    azurerm_role_assignment.function_runtime_account,
    azurerm_role_assignment.function_runtime_queue,
    azurerm_role_assignment.function_runtime_table,
    azurerm_role_assignment.function_storage,
  ]
}

resource "azurerm_service_plan" "function" {
  name                = "${var.project_name}-asp"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "P0v3"
  tags                = var.tags
}

resource "azurerm_linux_function_app" "main" {
  name                                           = local.function_app_name
  resource_group_name                            = azurerm_resource_group.main.name
  location                                       = azurerm_resource_group.main.location
  service_plan_id                                = azurerm_service_plan.function.id
  storage_account_name                           = azurerm_storage_account.function.name
  storage_uses_managed_identity                  = true
  content_share_force_disabled                   = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = azurerm_subnet.function.id
  tags                                           = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.function.id]
  }

  key_vault_reference_identity_id = azurerm_user_assigned_identity.function.id

  site_config {
    vnet_route_all_enabled = true

    application_stack {
      python_version = "3.11"
    }

    ip_restriction_default_action = "Deny"

    ip_restriction {
      name       = "AllowMyIP"
      ip_address = var.allowed_ip_address
      action     = "Allow"
      priority   = 100
    }

    ip_restriction {
      name        = "AllowAzurePortal"
      service_tag = "AzurePortal"
      action      = "Allow"
      priority    = 150
    }

    ip_restriction {
      name        = "AllowAzureCloud"
      service_tag = "AzureCloud"
      action      = "Allow"
      priority    = 160
    }

    ip_restriction {
      name                      = "AllowAppService"
      virtual_network_subnet_id = azurerm_subnet.appservice.id
      action                    = "Allow"
      priority                  = 200
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME              = "python"
    AzureWebJobsStorage__accountName      = azurerm_storage_account.function.name
    AzureWebJobsStorage__credential       = "managedidentity"
    AzureWebJobsStorage__clientId         = azurerm_user_assigned_identity.function.client_id
    AZURE_CLIENT_ID                       = azurerm_user_assigned_identity.function.client_id
    STORAGE_ACCOUNT_NAME                  = azurerm_storage_account.docs.name
    STORAGE_CONTAINER_NAME                = azurerm_storage_container.documents.name
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
  }

  depends_on = [
    time_sleep.function_rbac_propagation,
    azurerm_private_endpoint.function_storage_blob,
    azurerm_private_endpoint.function_storage_queue,
    azurerm_private_endpoint.function_storage_table,
  ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# App Service — Backend (FastAPI) & Frontend (Streamlit)
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_service_plan" "appservice" {
  name                = "${var.project_name}-app-asp"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = var.tags
}

# --- Backend App Service (FastAPI) ---------------------------------------------
resource "azurerm_linux_web_app" "backend" {
  name                = local.backend_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.appservice.id

  virtual_network_subnet_id = azurerm_subnet.appservice.id

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.backend.id]
  }

  site_config {
    always_on = false
    application_stack {
      python_version = "3.11"
    }
    app_command_line       = "uvicorn app.main:app --host 0.0.0.0 --port 8000"
    vnet_route_all_enabled = true

    ip_restriction_default_action = "Deny"

    ip_restriction {
      name       = "AllowMyIP"
      ip_address = var.allowed_ip_address
      action     = "Allow"
      priority   = 100
    }

    ip_restriction {
      name        = "AllowAzurePortal"
      service_tag = "AzurePortal"
      action      = "Allow"
      priority    = 150
    }

    ip_restriction {
      name                      = "AllowFrontend"
      virtual_network_subnet_id = azurerm_subnet.appservice.id
      action                    = "Allow"
      priority                  = 200
    }
  }

  app_settings = {
    "SEARCH_ENDPOINT"                = "https://${azurerm_search_service.main.name}.search.windows.net"
    "SEARCH_INDEX_NAME"              = "documents-index"
    "SEARCH_INDEXER_NAME"            = "documents-indexer"
    "OPENAI_ENDPOINT"                = azurerm_cognitive_account.openai.endpoint
    "OPENAI_DEPLOYMENT_NAME"         = azurerm_cognitive_deployment.gpt4o.name
    "OPENAI_API_VERSION"             = "2024-10-21"
    "AZURE_CLIENT_ID"                = azurerm_user_assigned_identity.backend.client_id
    "WEBSITES_PORT"                  = "8000"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
  }

  lifecycle {
    ignore_changes = [app_settings["DOCKER_REGISTRY_SERVER_URL"]]
  }

  tags = var.tags
}

# --- Frontend App Service (Streamlit) ------------------------------------------
resource "azurerm_linux_web_app" "frontend" {
  name                = local.frontend_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.appservice.id

  virtual_network_subnet_id = azurerm_subnet.appservice.id

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  site_config {
    always_on = false
    application_stack {
      python_version = "3.11"
    }
    app_command_line       = "python -m streamlit run app.py --server.port 8000 --server.address 0.0.0.0 --server.headless true"
    vnet_route_all_enabled = true
  }

  app_settings = {
    "BACKEND_URL"                    = "https://${azurerm_linux_web_app.backend.default_hostname}"
    "FUNCTION_APP_URL"               = "https://${azurerm_linux_function_app.main.default_hostname}/api"
    "WEBSITES_PORT"                  = "8000"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
  }

  tags = var.tags
}
