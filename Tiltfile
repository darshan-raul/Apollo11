docker_build("payment", "code/payment")
docker_build("movie", "code/movie")

k8s_yaml(['stages/stage-5/payment/app/payment-configmap.yaml','stages/stage-5/payment/app/payment-secret.yaml','stages/stage-5/payment/app/payment-service.yaml','stages/stage-5/payment/app/payment-deployment.yaml','stages/stage-5/payment/db/payment-db-data-persistentvolumeclaim.yaml', 'stages/stage-5/payment/db/payment-db-secret.yaml','stages/stage-5/payment/db/payment-db-service.yaml','stages/stage-5/payment/db/payment-db-statefulset.yaml'])
k8s_yaml(['stages/stage-5/movie/app/movie-configmap.yaml','stages/stage-5/movie/app/movie-secret.yaml','stages/stage-5/movie/app/movie-service.yaml','stages/stage-5/movie/app/movie-deployment.yaml','stages/stage-5/movie/db/movie-db-data-persistentvolumeclaim.yaml', 'stages/stage-5/movie/db/movie-db-secret.yaml','stages/stage-5/movie/db/movie-db-service.yaml','stages/stage-5/movie/db/movie-db-statefulset.yaml'])
