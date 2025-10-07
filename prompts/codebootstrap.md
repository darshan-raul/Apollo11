Giving you context of infra of a app I want to build for k8s. I want to create a apollo11 space astronaut onboarding app. You need to create code [seperate folder for each microservice] and docker compose and k8s manifests for me. 


Microservices:

- Python frontend for the user to access. fastapi and any ui toolkit 
- Golang Core api with which the frontend will talk to
- Simulator service - python - for now just gets a request from core api [through redis pubsub] and sends back a response from redis too
- Redis pubsub
- Postgres Db where the data will be stored
- A admin dashboard in python - streamlit



The flow:

- User connects on  python dashboard [inbuilt postgres based user auth for now, i will integrate keycloak later]
- They are presented with 11 stages of onboarding [come up with 11 stages on how astornauts can be onboarded with stage 11 being the final one]
- User starts with first stage, the golang api sends a request to simulator service through redis
- The simulator service gives random response back [through redis to golang] where 80% are success, 20% failures
- The golang api marks this stage progress for that particular user in db and unlocks them for next stage. the next stage is available only if the prev is successful
- Python admin dashboard will be used seperately just to view the data, throw in some user stat dashboards.