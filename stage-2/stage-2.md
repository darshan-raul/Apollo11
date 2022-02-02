## Initial plan to run graphql api and go rest api on minikube

> Tip: donot use anything other then fastapi,docker,k8s official docs to do this
> NOTE: first test these two api's locally to see if they can talk to each other.

## Python graphql api:


- [ X ] Create docker file
- [ X ] Build docker image with Dockerfile
    ```
    docker build -t fastapi-graphql
    ```
- [ X ] run the docker container locally and check if everything works fine
- [ X ] set docker env to minikube: `eval $(minikube docker-env)`
- [ X ] build the docker image in minikube
- [ ] Run the pod once and portforward it and check if working fine
    ```
    kubectl run fastapi --image fastapi-graphql --image-pull-policy='Never' --port 8000
    kubectl get po
    kubectl port-forward pod/fastapi 8000:8000
    ```
- [ X ] create configmap:
- [ X ] create secret:
- [ ] create a deployment for this docker image:
    - [ X ] keep appropriate imagepullpolicy  
    - [ X ] use the config map
    - [ X ] use the secret
    - [ X ] have livenessprobe [ensure healthcheck endpoint is there]
    - [ X ] have readinessprobe [ensure readiness file is there]
    - [ X ] have startupprobe [ensure readiness file is there]
    - [ ] have proper requests constraint
    - [ ] have proper limit constraint
    ```
    restart deployment whenever you update the image:
        k rollout restart deployment/fastapi
    ```
- [ ] Test the deployment:
    - [ ] update the code and create new image with v1 tag
    - [ ] rollout this deployment
    - [ ] check the status of the rollout
    - [ ] rollback to the prev deployment
    - [ ] check the rollout status

- [ ] HPA:
    - [ ] based on CPU utilization
- [ ] Load testing : locust
- [ ] create ClusterIP service
    - [ ] follow best practices
- [ ] Port forward and check if API works properly

## GO api:


- [ X ] Create docker file
- [ X ] Build docker image with Dockerfile
- [ X ] run the docker container locally and check if everything works fine
- [ X ] set docker env to minikube: `eval $(minikube docker-env)`
- [ X ] build the docker image in minikube
- [ X ] create configmap
- [ X ] create secret
- [ X ] create a deployment for this docker image:
    - [ X ] keep appropriate imagepullpolicy  
    - [ X ] have livenessprobe
    - [ X ] have readinessprobe
    - [ ] have proper requests constraint
    - [ ] have proper limit constraint
- [ ] HPA:
    - [ ] based on CPU utilization
- [ X ] This service must connect to the Python fastapi clusterip service
    - keep the fastapi clusterip service as endpoint for go api to connect
- [ X ] create NodePort service
- [ X ] check if API works properly with integration with FastAPi backend


## Helm:

- [ ] create a simple helm package
- [ ] helm install and check if all the above components are created

## Kustomize:

- [ ] learn kustomize and see if that approach is better

## Github actions:

- [ ] Test for python api
- [ ] Test for Go api

## Argocd:

- [ ] 