"""
Generate sample PDF documents for testing the Azure AI Search indexer.

Creates 3 PDFs with distinct, verifiable content in the sample-docs/ directory.
Doc 1 is designed to be updated later to test change detection.
"""

import os
from fpdf import FPDF

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "sample-docs")


def create_pdf(filename: str, title: str, content: str):
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 10, title, new_x="LMARGIN", new_y="NEXT")
    pdf.ln(5)
    pdf.set_font("Helvetica", size=11)
    pdf.multi_cell(0, 6, content)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    filepath = os.path.join(OUTPUT_DIR, filename)
    pdf.output(filepath)
    print(f"  Created {filepath}")


def main():
    print("Generating sample PDFs...\n")

    # Doc 1: Company Policy (will be updated to test change detection)
    create_pdf(
        "doc1-company-policy.pdf",
        "Contoso Company Policy Manual",
        """Section 1: Remote Work Policy
Contoso employees are permitted to work remotely up to three days per week. Remote work \
arrangements must be approved by the employee's direct manager. All remote workers must \
maintain a dedicated workspace and reliable internet connection.

The core working hours are 10:00 AM to 3:00 PM in the employee's local time zone. Employees \
must be available during these hours for meetings and collaboration.

Section 2: Expense Reimbursement
Travel expenses must be submitted within 30 days of the trip. The daily meal allowance is $75 \
for domestic travel and $100 for international travel. All expenses over $50 require a receipt.

Hotel bookings should be made through the company's preferred travel portal. First-class air \
travel is not permitted unless specifically approved by a VP or above.

Section 3: Annual Leave
All full-time employees receive 20 days of paid annual leave per year. Leave requests must be \
submitted at least two weeks in advance for periods longer than 3 days. Unused leave can be \
carried over up to a maximum of 5 days into the following year.""",
    )

    # Doc 2: Product FAQ
    create_pdf(
        "doc2-product-faq.pdf",
        "Contoso Widget Pro - Frequently Asked Questions",
        """Q: What is the Contoso Widget Pro?
A: The Contoso Widget Pro is our flagship productivity device that combines task management, \
time tracking, and team collaboration features into a single hardware device with a 7-inch \
touchscreen display.

Q: What is the battery life of the Widget Pro?
A: The Widget Pro has an 18-hour battery life under normal usage conditions. With the power \
saver mode enabled, it can last up to 24 hours.

Q: Is the Widget Pro waterproof?
A: The Widget Pro has an IP67 water resistance rating, meaning it can withstand submersion in \
1 meter of water for up to 30 minutes. However, it is not designed for underwater use.

Q: What operating system does the Widget Pro use?
A: The Widget Pro runs ContosoOS 4.2, a custom operating system designed specifically for \
productivity devices. It supports third-party app installation through the Contoso App Store.

Q: How much does the Widget Pro cost?
A: The Widget Pro starts at $499 for the base model with 128GB storage. The Pro Plus model \
with 256GB storage and cellular connectivity is available for $699.

Q: What warranty does the Widget Pro come with?
A: Every Widget Pro includes a 2-year manufacturer warranty covering hardware defects. Extended \
warranty plans of 3 and 5 years are available for purchase.""",
    )

    # Doc 3: Technical Specification
    create_pdf(
        "doc3-technical-spec.pdf",
        "Project Aurora - Technical Specification",
        """1. System Overview
Project Aurora is a cloud-native microservices platform designed for processing real-time \
sensor data from IoT devices. The system handles up to 1 million events per second with \
sub-100ms end-to-end latency.

2. Architecture Components
2.1 Ingestion Layer: Apache Kafka clusters with 12 brokers, configured with a replication \
factor of 3. Topic retention is set to 7 days. Messages use Avro serialization.

2.2 Processing Layer: Apache Flink streaming jobs running on Kubernetes. Auto-scaling is \
configured from 4 to 64 task manager pods based on throughput metrics.

2.3 Storage Layer: Time-series data is stored in Apache Cassandra with a 90-day retention \
policy. Aggregated metrics are stored in PostgreSQL for dashboard queries.

2.4 API Layer: GraphQL API built with Apollo Server, deployed as containerized services. \
Rate limiting is set to 1000 requests per minute per API key.

3. Security Requirements
All inter-service communication must use mTLS. External API access requires OAuth 2.0 \
bearer tokens. Data at rest is encrypted using AES-256. Audit logs are retained for 1 year.

4. Performance Targets
- Ingestion throughput: >= 1M events/second
- P99 processing latency: < 100ms
- Data query response time: < 500ms for 95th percentile
- System uptime SLA: 99.95%""",
    )

    print(f"\nAll PDFs created in: {os.path.abspath(OUTPUT_DIR)}")


if __name__ == "__main__":
    main()
