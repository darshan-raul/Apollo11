## Intro

- GitHub Actions is a continuous integration and continuous delivery (CI/CD) platform that allows you to automate your build, test, and deployment pipeline. 


## Features:
- GitHub provides Linux, Windows, and macOS virtual machines to run your workflows, 
- or you can host your own self-hosted runners in your own data center or cloud infrastructure.


## Main components:

### Workflow:

- A workflow is a configurable automated process that will run one or more jobs. 
Workflows are **defined by a YAML file** checked in to your repository and will run when 
    - triggered by an event in your repository, 
    - or they can be triggered manually, 
    - or at a defined schedule.

- Your **repository can have multiple workflows in a repository**, each of which can perform a different set of steps.


### Workflow components:
- You can configure a GitHub Actions workflow to be triggered when an **event** occurs in your repository, such as a pull request being opened or an issue being created.
- Your workflow contains one or more **jobs** which can **run in sequential order or in parallel**.
- **Each job** will run inside its own virtual machine runner, or inside a container, and **has one or more steps that either run a script that you define or run an action**, which is a reusable extension that can simplify your workflow.
    - Steps are executed in order and are dependent on each other. 
    - Since each step is executed on the same runner, you can share data from one step to another. 

### Runners

- A runner is a server that runs your workflows when they're triggered. 
- Each runner can run a single job at a time. GitHub provides Ubuntu Linux, Microsoft Windows, and macOS runners to run your workflows; 

> each workflow run executes in a fresh, newly-provisioned virtual machine

## Dependency:

- Steps are executed in order and are dependent on each other.
- by default, jobs have no dependencies and run in parallel with each other. 
- You can configure a job's dependencies with other jobs; 
- When a job takes a dependency on another job, it will wait for the dependent job to complete before it can run.