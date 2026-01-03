# Cloud Resume: Serverless Portfolio on AWS

## 1. Project Overview
This project is a serverless full-stack application that hosts my professional resume on AWS. It demonstrates the use of cloud-native architecture, automated quality checks, and advanced observability. The website includes a dynamic "visitor counter" that updates in real-time, utilizing a purely serverless backend.

**Live Demo:** [https://vb-web.in/]

---

## 2. Architecture
The solution uses a decoupled client-server architecture hosted entirely on AWS.

### Architecture Diagram
<img width="1830" height="434" alt="cloud-resume-acrch-diagram" src="https://github.com/user-attachments/assets/75f54e38-cb12-4b11-ad81-e708e63cba31" />

### High-Level Workflow:
1.  **Frontend:** Static files (HTML, CSS, JS) are stored in an **S3 Bucket**.
2.  **Content Delivery:** **CloudFront** acts as a CDN to cache content globally and enforce HTTPS via an **ACM Certificate**.
3.  **DNS:** **Route 53** manages the domain name resolution.
4.  **Backend Trigger:** JavaScript on the frontend triggers an API call to **API Gateway**.
5.  **Compute:** API Gateway triggers a **Lambda function** (written in Python).
6.  **Database:** The Lambda function atomically updates and retrieves the visitor count from a **DynamoDB** table.

---

## 3. Tech Stack

| Domain | Technology / Service |
| :--- | :--- |
| **Frontend** | HTML5, CSS3, JavaScript |
| **Cloud Storage** | AWS S3 (Static Website Hosting) |
| **CDN & Security** | AWS CloudFront, AWS Certificate Manager (ACM) |
| **DNS** | AWS Route 53 |
| **Compute (Backend)** | AWS Lambda |
| **API Management** | AWS API Gateway (REST/HTTP API) |
| **Database** | AWS DynamoDB (NoSQL) |
| **Code Quality** | Prettier, Husky |
| **Observability** | AWS CloudWatch (Logs, Alarms, Dashboards, Synthetics), AWS X-Ray |
| **Version Control** | Git & GitHub |
| **CI/CD** | GitHub Actions |

---

## 4. Key Features & Implementation Details

### A. Secure Static Hosting (Frontend)
* **S3 Bucket Policies:** Configured to block public access, allowing read access only via the CloudFront Origin Access Control (OAC).
* **Custom Domain:** Configured via Route 53 with an SSL/TLS certificate managed by ACM for secure HTTPS communication.

### B. Serverless Backend (API & Database)
* **Visitor Counter:** A REST API endpoint fetches and increments a specific item in the DynamoDB table.
* **CORS Configuration:** API Gateway is configured to only allow requests from the specific frontend domain.
* **Atomic Counter:** DynamoDB `ADD` operations are used to ensure concurrent visitors are counted accurately.

### C. Quality Assurance & Formatting
* **Automated Formatting:** **Prettier** is configured to ensure consistent code style across HTML, CSS, and JS files.
* **Git Hooks:** **Husky** is implemented to run pre-commit hooks. This prevents unformatted code from being committed to the repository, ensuring a clean codebase.

### D. Observability & Monitoring
To ensure system reliability and ease of debugging, a robust observability strategy was implemented:
* **Dashboards:** A custom **CloudWatch Dashboard** aggregates key metrics (API Latency, Visitor Count, Error Rates) into a single visual pane.
* **Canary Synthetics:** **CloudWatch Synthetics** (Canary) is deployed to run scheduled heartbeat scripts. This simulates user traffic to verify that the website endpoint is reachable and the API is responsive.
* **Distributed Tracing:** **AWS X-Ray** is enabled to visualize the request path and identify bottlenecks.
* **Structured Logging:** **CloudWatch Logs** capture execution details from the Lambda function.

---

## 5. Automation & CI/CD Pipeline
The project utilizes **GitHub Actions** for continuous integration and deployment.

### Workflow Steps:
1.  **Checkout Code:** Pulls the latest repository code.
2.  **Formatting Check:** Runs the Prettier check. If the code does not meet style guidelines, the build fails.
3.  **Deploy:**
    * Syncs frontend assets to the S3 bucket.
    * Invalidates the CloudFront cache to ensure immediate content updates.
    * Updates the Lambda function code via AWS CLI commands.

---

## 6. How to Run Locally (Development)

Since this project relies on AWS services (DynamoDB, API Gateway), strictly "local" development requires mocking these services or connecting to the live cloud resources from your local machine.

**Prerequisites:**
* Node.js & npm (for Prettier/Husky).
* Python 3.x (for Backend logic).
* AWS CLI configured (if running backend scripts against live AWS).

### Step 1: Clone the Repository
```bash
git clone https://github.com/VikramBabariya/cloud-resume.git
cd cloud-resume-challenge
```

### Step 2: Install Frontend Dependencies
```bash
npm install
# This installs Prettier and sets up Husky hooks automatically
```

### Step 3: Run the Frontend
```
# You can utilize some local http server to open index.html file in the browser
```

## 7. Future Improvements
* Migrate manual infrastructure setup to Terraform or AWS CDK for full Infrastructure as Code (IaC).
* Implement a Dark/Light mode toggle for the UI.
* Add authentication for an admin dashboard to view detailed visitor analytics.
