docker_build("payment", "code/payment")
docker_build("movie", "code/movie")
docker_build("theatre", "code/theatre")
docker_build("booking", "code/booking")
docker_build("dashboard", "code/dashboard")
docker_build("pushmetric", "code/pushmetric")

k8s_yaml(['stages/stage-3/payment/app/payment-configmap.yaml','stages/stage-3/payment/app/payment-secret.yaml','stages/stage-3/payment/app/payment-service.yaml','stages/stage-3/payment/app/payment-deployment.yaml','stages/stage-3/payment/db/payment-db-data-persistentvolumeclaim.yaml', 'stages/stage-3/payment/db/payment-db-secret.yaml','stages/stage-3/payment/db/payment-db-service.yaml','stages/stage-3/payment/db/payment-db-statefulset.yaml'])
k8s_yaml(['stages/stage-3/movie/app/movie-configmap.yaml','stages/stage-3/movie/app/movie-secret.yaml','stages/stage-3/movie/app/movie-service.yaml','stages/stage-3/movie/app/movie-deployment.yaml','stages/stage-3/movie/db/movie-db-data-persistentvolumeclaim.yaml', 'stages/stage-3/movie/db/movie-db-secret.yaml','stages/stage-3/movie/db/movie-db-service.yaml','stages/stage-3/movie/db/movie-db-statefulset.yaml'])
k8s_yaml(['stages/stage-3/theatre/app/theatre-configmap.yaml','stages/stage-3/theatre/app/theatre-secret.yaml','stages/stage-3/theatre/app/theatre-service.yaml','stages/stage-3/theatre/app/theatre-deployment.yaml','stages/stage-3/theatre/db/theatre-db-data-persistentvolumeclaim.yaml', 'stages/stage-3/theatre/db/theatre-db-secret.yaml','stages/stage-3/theatre/db/theatre-db-service.yaml','stages/stage-3/theatre/db/theatre-db-statefulset.yaml'])
k8s_yaml(['stages/stage-3/dashboard/app/dashboard-configmap.yaml','stages/stage-3/dashboard/app/dashboard-secret.yaml','stages/stage-3/dashboard/app/dashboard-service.yaml','stages/stage-3/dashboard/app/dashboard-deployment.yaml'])
k8s_yaml(['stages/stage-3/booking/app/booking-configmap.yaml','stages/stage-3/booking/app/booking-secret.yaml','stages/stage-3/booking/app/booking-service.yaml','stages/stage-3/booking/app/booking-deployment.yaml','stages/stage-3/booking/db/booking-db-data-persistentvolumeclaim.yaml', 'stages/stage-3/booking/db/booking-db-secret.yaml','stages/stage-3/booking/db/booking-db-service.yaml','stages/stage-3/booking/db/booking-db-statefulset.yaml'])
k8s_yaml(['stages/stage-3/pushmetric/pushmetric-configmap.yaml','stages/stage-3/pushmetric/pushmetric-cronjob.yaml'])

