minikube addons enable ingress
kubectl get pods -n kube-system

kubectl create deployment web --image=gcr.io/google-samples/hello-app:1.0
kubectl expose deployment web --type=NodePort --port=8080
kubectl get service web
minikube service web --url

kubectl apply -f ingress1.yml 
kubectl get ingress


kubectl create deployment web2 --image=gcr.io/google-samples/hello-app:2.0
kubectl expose deployment web2 --port=8080 --type=NodePort



