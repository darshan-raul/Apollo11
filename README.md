
# Apollo 11

11 stage plan to know end-to-end of k8s/cloudnative ecosystem

`First do it -> Then do it right -> Then do it better`

![DOIT](images/51mXr8x14bL.jpg)

**Stages**:

- Stage 1: Basics + Local setup

- Stage 2: Rest api + backend in local k8s cluster

- Stage 3: Routing using ingress controller

- Stage 4: Move on from Minikube/Docker

- Stage 5: Helm packaging

- Stage 6: Service Mesh

- Stage 7: Monitoring + Observability + Tracing

- Stage 8: Deployment/Gitops + Autoscaling

- Stage 9: Event driven architecture

- Stage 10: Testing + Chaos Engineering + Backup and Restore

- Stage 11: Security and Compliance

We will be creating a simple rest api in Golang and then extending it with a frontend and backend.
Along the way we will explore all the services and features in the k8s ecosystem to get a handson on how to create a Complete app architecture

--------------------------------

Pre-requisites
--------------------------------

[You need to be NASA before you can be in the apollo program ;) ]

Some basics have to be in place:

- Linux :
  - <https://linuxjourney.com/>
  - <https://developer.ibm.com/tutorials/linux-basics-and-commands/>

- Vim: (Coz there will not always be ide)
  - <https://www.youtube.com/watch?v=ggSyF1SVFr4>

- Yaml: ( k8s is all yaml)
  - <https://www.youtube.com/watch?v=1uFVr15xDGg>
  - <https://developer.ibm.com/tutorials/yaml-basics-and-usage-in-kubernetes/>

<https://github.com/arialdomartini/Back-End-Developer-Interview-Questions>

# Stage 1: Basics + Local setup [ 2 weeks ]


> Goal: Good enough knowledge of k8s and golang to get started

## 1. Go Lang basics

**Note**: Go lang is **optional**. You can create the rest api's in Python or any other language as well.

Recommended videos to watch and follow along:

- [Go / Golang Full Course for Beginners | 2021](https://www.youtube.com/watch?v=1NF2LtWbA1g&t=1024s)
- [Introduction to Go Programming for beginners](https://www.youtube.com/watch?v=jpKysZwllVw&t=488s )
 
Once you have a fair amount of handson following the above two tutorials, 
follow this tour from go and then the cheatsheet to get an general overview:

- http://tour.golang.org/
- https://github.com/a8m/golang-cheat-sheet

You will also find my go learning scripts in `stage-1/go-learning`

**Bro Tip**: You commits pushed from laptop wont be visible in the github contributions. Yes we love green dots :D Follow this to setup GPG verified commits https://www.youtube.com/watch?v=4166ExAnxmo

**Other Sources**:
- [Why Golang is DevOps' Top Programming Language in 2021](https://www.youtube.com/watch?v=7pLqIIAqZD4)
- https://www.youtube.com/watch?v=N0fIANJkwic&t=425s
- https://www.youtube.com/watch?v=79NeEFURq_U
- [Learn Go Programming - Golang Tutorial for Beginners](https://www.youtube.com/watch?v=YS4e4q9oBaU)
-  [Golang Tutorials - Tech by Tim](https://www.youtube.com/playlist?list=PLzMcBGfZo4-mtY_SE3HuzQJzuj4VlUG0q) 
- [Go lang top usecases ](https://medium.com/geekculture/top-golang-use-cases-266b4ee5a37d)

## 2. Docker/Container Basics:

 Because even though docker is no more the only container runtime in town. Its still the best place to get to know about containers and explore them

- [Learn Docker in 7 Easy Steps - Full Beginner's Tutorial](https://www.youtube.com/watch?v=gAkwW2tuIqE)
- [you need to learn Docker RIGHT NOW!! // Docker Containers 101](https://www.youtube.com/watch?v=eGz9DS-aIeY)
- Do one of these full courses: 
  - [Docker Tutorial for Beginners FULL COURSE in 3 Hours](https://www.youtube.com/watch?v=3c-iBn73dDE)
  - [Docker for Beginners: Full Free Course!- KodeKloud ](https://www.youtube.com/watch?v=zJ6WbK9zFpI&t=3637s)
- Cover remaining gaps with these cheatsheets and articles:
  - https://github.com/wsargent/docker-cheat-sheet
  - https://developer.ibm.com/blogs/what-are-containers-and-why-do-you-need-them/
  - https://developer.ibm.com/tutorials/building-docker-images-locally-and-in-cloud/
  - `Run your app in production` section from <https://docs.docker.com/get-started/overview/>
  - [Docker explained in Sketches](https://dev.to/aurelievache/series/8105)

 Deep-dive:

- <http://docker-saigon.github.io/post/Docker-Internals/>
- [Docker Container Lifecycle and Commands | K21 Academy](https://www.youtube.com/watch?v=wqKRmbBeS24&list=WL&index=6)
- <https://developer.ibm.com/articles/true-benefits-of-moving-to-containers-1/>
- <https://developer.ibm.com/articles/true-benefits-of-moving-to-containers-2/>
- <https://developer.ibm.com/videos/dev-diaries-app-modernization-containers/>
- <https://gist.github.com/StevenACoffman/41fee08e8782b411a4a26b9700ad7af5> [best practices]

- <https://www.youtube.com/watch?v=RfL_CjXfQds> [Dockerless: Build and Run Containers with Podman and Systemd]

## 3.Kubernetes basics

- Take an overview of K8s:

  - [Kubernetes Explained in 100 Seconds](https://www.youtube.com/watch?v=PziYflu8cB8)
  - [you need to learn Kubernetes RIGHT NOW!!](https://www.youtube.com/watch?v=7bA0gTroJjw)
 <https://www.youtube.com/watch?v=8C_SCDbUJTg>

- Watch this video completely. Take notes:

  <https://www.youtube.com/watch?v=X48VuDVv0do&t=6088s>

- Get your hands dirty. This tutorial will give a good bootstrap on k8s operations

  - <https://kubernetes.io/docs/tutorials/kubernetes-basics/>

  - https://github.com/knrt10/kubernetes-basicLearning
  
  - Brisk through <https://kubernetes.io/docs/concepts>.
  (Coz reading the documentation for 15 mins is better than spending 2 hours on stackoverflow) :D
  
  The two tasks will make it pretty easy for you to understand the core concepts from the documentation. This will be just to consolidate those core concepts and collect more dots of k8s knowledge. In the later stages you will be able to connect those extra dots as well.
  
  

Networking

<https://rtfm.co.ua/en/kubernetes-clusterip-vs-nodeport-vs-loadbalancer-services-and-ingress-an-overview-with-examples/>

 Kubernetes Essential Tools: 2021 <https://itnext.io/kubernetes-essential-tools-2021-def12e84c572>
 <https://itnext.io/kubernetes-explained-deep-enough-1ea2c6821501>
 
 
 Optional:

- <https://betterprogramming.pub/k8s-a-closer-look-at-kube-proxy-372c4e8b090>
- <https://developer.ibm.com/videos/learn-the-history-and-fundamentals-of-kubernetes/>
- <https://medium.com/containermind/a-beginners-guide-to-kubernetes-7e8ca56420b6> [2018 article but covers lot of topics]
- <https://developer.ibm.com/articles/kubernetes-networking-what-you-need-to-know/>
- Complete all scenarios here: <https://www.katacoda.com/loodse/courses/kubernetes>
- <https://www.youtube.com/watch?v=XJufs3ZZBVY> [How to Setup a 3 Node Kubernetes Cluster for CKA Step by Step]

## Install minikube & understand the basics:
 <https://kubernetes.io/docs/tutorials/hello-minikube/>

 > Note: Minikube is the simplest way to start a local k8s cluster. There are many other ways like kind(Kubernetes in Docker) ,k3s,microk8s amongst others.<https://developer.ibm.com/blogs/options-to-run-kubernetes-locally/>

 <https://kubernetes.io/docs/reference/kubectl/overview/>

## K8s yaml syntax:

Its all yaml!!

- https://www.mirantis.com/blog/introduction-to-yaml-creating-a-kubernetes-deployment/>

- https://www.youtube.com/watch?v=1rwCkFTjikw> [YAML Tips for Kubernetes]
- https://www.youtube.com/watch?v=5gsHYdiD6v8> [Simplify Kubernetes YAML with Kustomize]
- https://boxunix.com/2020/05/15/a-better-way-of-organizing-your-kubernetes-manifest-files/

## Optional

- Check all the terms and glossary <https://kubernetes.io/docs/reference/glossary/?all=true>


# Stage 2: Rest api + backend in local k8s cluster [ 2 weeks ]


> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API

1. Create namespace "application"

 `kubectl create namespace mynamespace`

2. Create a simple go rest API [or in python]

 <https://www.youtube.com/watch?v=MKkokYpGyTU> [ Introduction to HTTP with Go : Our first microservice]

<https://tutorialedge.net/golang/basic-rest-api-go-fiber/>

<https://www.youtube.com/playlist?list=PLmD8u-IFdreyh6EUfevBcbiuCKzFk0EW_>

3. Build docker image with it

 > [Figure how to link local image repo in minikube](https://stackoverflow.com/questions/42564058/how-to-use-local-docker-images-with-minikube)

> Create everything below using configuration yaml

<https://blog.usejournal.com/useful-tools-for-better-kubernetes-development-87820c2b9435?gi=7295c99c2a0c>

Create a deployment and expose as external service

Should be able to access it from browser as <externalip>.port

Create namespace "nosql"
mongodb deployment
Expose mongodb as internal service
Mongodb credentials stored in secrets.
Then referenced from mongoexpress deployment
(Need to create secrets before you can use them)

Learn peristent volumes and stateful sets and change mongodb to that instead of deployment

Create a config map of non sensitive values if needed
<https://www.youtube.com/watch?v=o-gXx7r7Rz4> [Configuration management in Kubernetes for beginners]
Mongo express deployment
Expose mongodbexpress as external service

Change go code to interact with mongodb
Make the go service interact with mongodb service
Crud operation should work

Create namespace front end
Add a small front end app to the make calls to go api

Create local image

Create it as deployment and load env variables from a config map
Expose it as external service

--------------------------------

Stage 3: Routing using ingress controller [ 1 week ]
--------------------------------

> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API

https://betterprogramming.pub/do-faster-development-and-testing-on-kubernetes-apps-with-telepresence-b7eac604dca4

https://github.com/cdk8s-team/cdk8s

Create ingress rules for sample url ---> gobuydoge.com
/Frontend will take to frontend external service
/Backend will take to backeelnd external service

Create ingress controller to control all the routes
On local machine add entry for gobuydoge.com to the ingress controller ip

Gobuydoge.com/frontend should show frontend
Gobuydoge.com/backend should show backend

Extra:

- Have a look at various other ingress controllers: <https://docs.google.com/spreadsheets/d/191WWNpjJ2za6-nbG4ZoUMXMpUK8KlCIosvQB0f-oq3k/htmlview?pru=AAABdXUHlbs*g6XkyoZXhanlhRazst77Xw>
- Try Traefik v2 ingress controller

--------------------------------

Stage 4: Move on from Minikube/Docker
--------------------------------

> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API.

Move to creating two virtual machines(vagrant)
One will be master
One will be worker

Learn kubernetes the hard way [ Create your own k8s cluster ]

- <https://www.youtube.com/watch?v=E3h8_MJmkVU> [Kubernetes Cluster Setup with Kubeadm in RHEL7 |CENTOS7 for beginner --2021]
- <https://www.youtube.com/watch?v=XJufs3ZZBVY> [ How to Setup a 3 Node Kubernetes Cluster for CKA Step by Step ]
<https://gabrieltanner.org/blog/ha-kubernetes-cluster-using-k3s>

Create control node components on master node

Install any other container runtime other than docker

- [Docker is no longer supported](https://blog.datacamp.engineering/understanding-the-kubernetes-docker-deprecation-notice-by-dummies-for-dummies-c9f2685486e0)

- <https://www.youtube.com/watch?v=bV5RcNiHlfw> [Kubernetes cluster with CRI-O container runtime | Step by step tutorial]

Run the same workload that was run on minikube

Run the above setup in either of a cloud k8s platform (manually for now):

- EKS
- AKS
- GKE
- Linode

Extra:

- Use buildah to build container images instead of
- Try different local k8s platforms: k3s,kind,microk8s.
- Aws eks infra building with CDK

--------------------------------

Stage 5: Helm packaging
--------------------------------

> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API

<https://developer.ibm.com/tutorials/helm-101-labs/>

- helm packages building
- Helmfile

- Optional:
  - Complete scenarios here: <https://www.katacoda.com/javajon/courses/kubernetes-tools>

--------------------------------

Stage 6: Service Mesh
--------------------------------

> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API

- Service mesh ISTIO

A service mesh, like the open source project Istio, is a way to control how different parts of an application share data with one another. Unlike other systems for managing this communication, a service mesh is a dedicated infrastructure layer built right into an app. This visible infrastructure layer can document how well (or not) different parts of an app interact, so it becomes easier to optimize communication and avoid downtime as an app grows.

<https://www.youtube.com/watch?v=hkR1M6qwpnw> [Istio in 5 minutes]
Istio Service Mesh Explained <https://www.youtube.com/watch?v=6zDrLvpfCK4>

<https://piotrminkowski.com/2021/07/12/multicluster-traffic-mirroring-with-istio-and-kind/>

--------------------------------

Stage 7: Monitoring + Observability + Tracing
--------------------------------

> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API
https://12factor.net/ -- 12 factor app

  - <https://developer.ibm.com/tutorials/debug-and-log-your-kubernetes-app/>
  - EFK Logging

- K8s monitoring

  - lens
  - prometheus
  - Tracing using opentelementry

--------------------------------

Stage 8: Testing + Deployment/Gitops + Autoscaling
--------------------------------

<https://tutorialedge.net/golang/intro-testing-in-go/>

<https://itnext.io/kubernetes-deployment-strategies-types-and-argo-rollouts-9d5f98e8b24e>
<https://blog.container-solutions.com/kubernetes-deployment-strategies>

> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API

- K8s Deployment strategy
  - CICD using github actions
  - DevSecops
  - TestOps
  - k8s misconfiguration from reaching production- datree

- Various deployment patterns in K8s
- gitops with flux v2

--------------------------------

Stage 9: Event driven architecture
--------------------------------

> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API

- Introduce a event bus or stream eg. Apache FLink and operate using same

--------------------------------

Stage 10: Testing + Chaos Engineering + Backup and Restore
--------------------------------

> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API

- DevSecOps
- inject failure into your Kubernetes clusters

--------------------------------

Stage 11: Security and Compliance + threat detection
--------------------------------

> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API

<https://kubernetes.io/docs/concepts/security/>

https://twitter.com/kubesploit

- Secure the cluster based on the 4C’s of cloud native security
<https://developer.ibm.com/articles/journey-to-kubernetes-security/>
<https://developer.ibm.com/blogs/basics-of-kubernetes-security/>

<https://developer.ibm.com/tutorials/installing-and-using-sysdig-falco/>

- Falco
- kubehunter
- Gatekeeper

- Enforce good practices using datree

<https://www.stackrox.com/post/2020/05/kubernetes-security-101/>

Apollo program continues: Go deeper in this space
--------------------------------

Write your own Kubernetes controller in Rust from scratch
<https://blog.frankel.ch/start-rust/6/>

> Goal: Rest api to interact with mongodb. mongoexpress to interact with mongodb. Frontend to interact with API

Explore Kubernetes Serverless:

- K-native
  <https://cloud.google.com/knative/>

- OpenFaas
  <https://www.openfaas.com/>

- Kubeless

 Optional:
  <https://www.katacoda.com/javajon/courses/kubernetes-serverless>

Openshift:

- <https://developer.ibm.com/videos/openshift-vs-kubernetes-for-developers/>

- Admission controllers/webhooks <https://www.youtube.com/watch?v=1mNYSn2KMZk>
- Kubernetes Operator

-- Try new tools and features:
 <https://github.com/grafana/tanka>

- <https://ymmt2005.hatenablog.com/entry/k8s-things> [47 Things To Become a Kubernetes Expert]
- <https://github.com/dgkanatsios/CKAD-exercises>
- <https://github.com/walidshaari/Kubernetes-Certified-Administrator>
- <https://github.com/walidshaari/Certified-Kubernetes-Security-Specialist>
- <https://github.com/ibrahimjelliti/CKSS-Certified-Kubernetes-Security-Specialist>

## Cheatsheets

- kubectl: <https://kubernetes.io/docs/reference/kubectl/cheatsheet/>

--------------------------------

## Labs

- <https://developer.ibm.com/tutorials/kubernetes-101-labs/>
- <https://labs.play-with-k8s.com/>#
- Complete all k8s scenarios in <https://www.katacoda.com/>

References
--------------------------------

- <https://github.com/tomhuang12/awesome-k8s-resources>
 <https://labs.play-with-k8s.com/>#
 <https://developer.ibm.com/components/kubernetes/series/kubernetes-learning-path/>

--------------------------------

Reading lists
--------------------------------

- Kubernetes
  - <https://kubernetes.io/case-studies/>

- Docker:
  - <https://developer.ibm.com/articles/containerization-of-legacy-applications/>

--------------------------------

Youtube Channels
--------------------------------

- [ That DevOps Guy] <https://www.youtube.com/channel/UCFe9-V_rN9nLqVNiI8Yof3w>

-

--------------------------------

Blogs
--------------------------------

<https://kubernetes.io/blog/>


--------------------------
Inspiring Articles for long term learning
--------------------------

https://typesense.org/blog/the-unreasonable-effectiveness-of-just-showing-up-everyday/
