docker_build("payment", "code/payment")
k8s_yaml(['stages/stage-5/payment/app/payment-configmap.yaml','stages/stage-5/payment/app/payment-secret.yaml','stages/stage-5/payment/app/payment-service.yaml','stages/stage-5/payment/app/payment-deployment.yaml','stages/stage-5/payment/db/payment-db-data-persistentvolumeclaim.yaml', 'stages/stage-5/payment/db/payment-db-secret.yaml','stages/stage-5/payment/db/payment-db-service.yaml','stages/stage-5/payment/db/payment-db-statefulset.yaml'])


