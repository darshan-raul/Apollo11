## EKS 

The most trusted way to start, run, and scale Kubernetes

 1 On cloud

1. Managed EKS cloud:
    - EC2
    - Fargate

3. Self Managed EKS distro 

2. On premises

2. Managed EKS Anywhere
   EKS on AWS OUTPOSTS
   Can add nodes running on AWS Local Zones , AWS Wavelength

## Features:
- Amazon EKS automatically manages the availability and scalability of the Kubernetes control plane nodes responsible for scheduling containers, managing application availability, storing cluster data, and other key tasks.

- EKS **supports AWS Fargate** to run your Kubernetes applications using serverless compute.
- Version support: 
    As new Kubernetes versions are released and validated for use with Amazon EKS, we **will support three stable Kubernetes versions** at any given time as part of the update process. Y

- You can use CloudTrail to view API calls to the Amazon EKS API. 
- Amazon EKS also delivers Kubernetes control plane logs to Amazon CloudWatch for analysis, debugging, and auditing.
- **EKS Connector**
    Amazon EKS allows you to connect any conformant Kubernetes cluster to AWS and visualize it in the Amazon EKS console. You can connect any conformant Kubernetes cluster, including Amazon EKS Anywhere clusters running on-premises, self-managed clusters on Amazon Elastic Compute Cloud (Amazon EC2), and other Kubernetes clusters running outside of AWS. 
- Amazon EKS is compliant with SOC, PCI, ISO, FedRAMP-Moderate, IRAP, C5, K-ISMS, ENS High, OSPAR, HITRUST CSF, and is a HIPAA eligible service.

## FAQS:

- Amazon EKS works by provisioning (starting) and managing the Kubernetes control plane and worker nodes for you. 
- At a high level, Kubernetes consists of two major components: 
    - a cluster of 'worker nodes' running your containers, and 
    - the control plane managing when and where containers are started on your cluster while monitoring their status.
- OS support: 
    - Amazon EKS supports Kubernetes-compatible Linux x86, ARM, and Windows Server operating system distributions. 
    - Amazon EKS provides optimized AMIs for Amazon Linux 2 and Windows Server 2019. 
    - EKS- optimized AMIs for other Linux distributions, such as Ubuntu, are available from their respective vendors 
- There are **two types of updates **you can apply to your Amazon EKS cluster: 
    - Kubernetes version updates and 
    - Amazon EKS platform version updates.
- Uptime:
    - Monthly Uptime Percentage of at least 99.95% during any monthly billing cycle (the "Service Commitment"). 
    - In the event Amazon EKS does not meet the Monthly Uptime Percentage commitment, you will be eligible to receive a Service Credit ( dollar credit)
    - uptime Less than 99.95% but greater than or equal to 99.0% - 10% service credit
    - uptime Less than 99.0% but greater than or equal to 95.0% - 25%  service credit
    - uptime Less than 95.0% -100%  service credit
## Pricing:


You pay **$0.10 per hour for each Amazon EKS cluster** that you create. You can use a single EKS cluster to run multiple applications by taking advantage of Kubernetes namespaces and IAM security policies. 


- If you are using Amazon EC2 (including with Amazon EKS managed node groups), you pay for AWS resources (e.g., EC2 instances or Amazon Elastic Block Store (EBS) volumes) you create to run your Kubernetes worker nodes. You only pay for what you use, as you use it; there are no minimum fees and no upfront commitments
- If you are using AWS Fargate, pricing is calculated based on the vCPU and memory resources used from the time you start to download your container image until the Amazon EKS pod terminates, rounded up to the nearest second. A minimum charge of one minute applies











- Can pause and resume deployments

- EBS CSI (container storage interface)
    - create storage class
    - create pvc
    - volume mount