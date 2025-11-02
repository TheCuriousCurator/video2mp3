sudo apt-get install libmysqlclient-dev

sudo mysql -u root < init.sql 

sudo mysql -u root 
    show databases;
    use auth;
    show tables;
    describe user;
    select * from user;

# build docker container
docker build .
# login
https://www.docker.com/
# login to docker desktop
- follow docker desktop notifications and follow instrutions
- generate pub key
- set pass
# create repository
dksahuji/video2mp3-auth:latest
# tag local docker image with a name
docker tag 919fd45d50350053da74716f6ab54b350c672d7b1ff93e7ff5abeb94c657b4ff dksahuji/video2mp3-auth:latest
# list all images
docker image ls
# push local docker image
docker push dksahuji/video2mp3-auth:latest

# start minikube
minikube start
# check minikube cluster
k9s
# create deployment.apps/auth, configmap/auth-configmap, secret/auth-secret, service/auth
- cd src/auth/manifests
- kubectl apply -f ./
- kubectl delete -f ./

![alt text](images/image-3.png)
![alt text](images/image-4.png)
# check in k9s two instance of auth service created
![alt text](images/image.png)

# you can go to an instance and press to enter shell
# show all env config
env 

# kubernetes
![alt text](images/image-1.png)

# scale replicas
kubectl scale deployment --replicas=6 service
![alt text](images/image-2.png)

- https://kubernetes.io/docs/concepts/overview/working-with-objects/
- https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/deployment-v1/
- https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/deployment-v1/#DeploymentSpec