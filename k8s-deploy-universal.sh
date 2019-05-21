#!/bin/bash
# This script will deploy your K8S manifests to K8S cluster using Bastion Hosts
# The script can expose the application with AWS ELB if Ingress is not exist
# The scrtip is verifying the commitId of the job and the builded artifact ( should be same! )
# V0.1 Denis Pesikov

IMAGE_VERSION=$(echo ${COMMIT,,} | cut -c1-7)
WORKSPACE=$WORKSPACE/infra
##
# Choose the Bastion ENV
##
case "$ENV" in
    *dev2*)
      BASTION_IP=$IP_DEV2
              ;;
    *dev*)
      BASTION_IP=$IP_DEV
              ;;
     *stg*)
      BASTION_IP=$IP_STG
              ;;
     *prod*)
      BASTION_IP=$IP_PROD
              ;;
     *)
      echo "Unknown environment"
      exit 1
              ;;
esac

##
# AWS ecr check if image exits
##
IMAGE_META="$( aws ecr describe-images --repository-name=$ECR_REPO_NAME --image-ids=imageTag=$IMAGE_VERSION 2> /dev/null )"
if [[ $? == 0 ]]; then
    IMAGE_TAGS="$( echo ${IMAGE_META} | jq '.imageDetails[0].imageTags[0]' -r )"
    echo "OK proceed with $ECR_REPO_NAME:$IMAGE_VERSION"
else
    echo "The image :$ECR_REPO_NAME:$IMAGE_VERSION not found"
    exit 1
fi

##
# change the image id && namespace in deploy file
##
sed -i -e "s/COMMITID/$IMAGE_VERSION/g" $WORKSPACE/deploy/$POD_NAME/$ENV/$POD_NAME.yml
sed -i -e "s/FULLID/$COMMIT/g" $WORKSPACE/deploy/$POD_NAME/$ENV/$POD_NAME.yml

## David Alvez
# ansible vault secrets decrypt
##
if [ -f $WORKSPACE/deploy/$POD_NAME/$ENV/secret.yml ]; then
  echo "Decrypting secrets..."
  ansible-vault decrypt $WORKSPACE/deploy/$POD_NAME/$ENV/secret.yml
fi
##
# check the connection to bastion host
##
echo "Waiting for SSH..."
until nc -z $BASTION_IP 22
do
	echo "."
	sleep 1
done

##
# Start the deployment
##
echo "Importing the env to bastion server" # Need to import the env variables so Bastion will know the commitId and imageDetails
env > $WORKSPACE/deploy/jenkins_env.conf
echo "Copying files to the bastion instance $BASTION_IP."
rsync -avz --delete $WORKSPACE/deploy/* $SSH_USER@$BASTION_IP:~/deploy  #FIXME? for app path only

## David Alvez
# delete secret file from jenkins workspace
##

if [ -f $WORKSPACE/deploy/$POD_NAME/$ENV/secret.yml ]; then
  echo "Deleting secret file from jenkins"
  rm -f $WORKSPACE/deploy/$POD_NAME/$ENV/secret.yml
fi

##
# Run the update
##
echo "Starting the upgrade"
ssh -oStrictHostKeyChecking=no $SSH_USER@$BASTION_IP << 'ENDSSH'

##
# Import Jenkins env vars
##
cd ~/deploy/
while read line ; do DEPLOY_ENV=$(echo $line | cut -d "=" -f 1) ; if [ ! -v $DEPLOY_ENV  ]; then echo "Need to set $line" && export $line ;  fi ; done < jenkins_env.conf
export TERM=xterm # Just need this , don't ask why

##
# GOTO workdir
##
cd ~/deploy/$POD_NAME/$ENV/
pwd

## Define the NameSpace
# check that all the namespaces across manifests are the same
Uniq=$(grep -h "namespace" *.yml | cut -d ":" -f 2 | sort | uniq -c | wc -l | tr -d '[:space:]')
if [[ $Uniq -gt 1 ]];then
  echo "Your manifests having non unique namespace"
  exit -1
fi
# Fetching the NameSpace definition from the pod manifest
NameSpace=$(grep namespace "$POD_NAME.yml" | cut -d ":" -f 2 |tr -d '[:space:]')
PossibleNameSpaces=$(kubectl get namespaces | awk '{print $1}' | tr '\r\n' ' ')
if [[ "$PossibleNameSpaces" =~ "$NameSpace" ]];then
  echo "Defined NAMESPACE=$NameSpace"
else
  echo "NAMESPACE $NameSpace is not part of $PossibleNameSpaces, I will not continue"
  exit -1
fi
##

##
# Check if there is secret file to be handled #
##
if [ -f secret.yml ]; then
   echo "secret for $POD_NAME is detected , going to apply it" # FIXME - not supporting secret rollback!
   kubectl -n "$NameSpace" delete -f secret.yml || true
   kubectl -n "$NameSpace" create -f secret.yml
else
   echo "No secret with the app continue to deploy $POD_NAME"
fi

##
# Apply new config
##
DEPLOYMENTS_COUNT=$(kubectl -n "$NameSpace" get deployments | grep $POD_NAME | wc -l |tr -d '[:space:]')
if [ $DEPLOYMENTS_COUNT -ge 1 ];then
  echo "#####"
  echo "The Deployment already exist , doing rollout"
  echo "#####"
	kubectl replace -f $POD_NAME.yml
	kubectl -n "$NameSpace" rollout status deployment $POD_NAME
else
  echo "#####"
	echo "Ok boss! 1st Deploy , applying the manifests"
  echo "#####"
	kubectl apply -f $POD_NAME.yml
	kubectl -n "$NameSpace" rollout status deployment $POD_NAME
fi

##
# Expose the container with ELB if Ingress not exist
##
IngresOn=$(if [ -f ingress.yml ] ; then grep -c Ingress ingress.yml ; fi)
if [ $IngresOn -lt 1 ] ; then
	echo "Will expose the deployment with AWS ELB"
	kubectl expose -n "$NameSpace" deployment $POD_NAME --type=LoadBalancer --port=$POD_PORT --target-port=$POD_PORT --name="$POD_NAME-public" || true
	POD_INGRESS=$(kubectl -n "$NameSpace" describe service $POD_NAME-public  | grep "Ingress" | cut -d ":" -f 2 | tr -d '[:space:]')
else
	echo "Will expose the deployment with K8S NodePort and Ingress"
  ServiceExist=$(kubectl get services -n "$NameSpace" -o name | grep -c $POD_NAME )
  IngressExist=$(kubectl get ingress -n "$NameSpace" -o name | grep -c $POD_NAME )
  if [ $ServiceExist -lt 1 ]; then
  kubectl -n "$NameSpace" expose deployment $POD_NAME --type=NodePort
  else
  echo "NodePort service for $POD_NAME is already configured, skipping."
  fi
  if [ $IngressExist -lt 1 ]; then
  kubectl apply -f ingress.yml
  else
  echo "Ingress service for $POD_NAME is already configured, skipping."
  fi
fi

##
# Fetch commit id and check if we are updated the pod
##
POD_PORT=$(grep "port:" $POD_NAME.yml | cut -d ":" -f 2 | tr -d '[:space:]')
# Get new commit id
if [ $IngresOn -lt 1 ] ; then
 echo "Checking pods commitid deployed with AWS ELB"
 sleep 10
 POD_ID=$(curl -s $POD_INGRESS:$POD_PORT/monitoring/info | egrep -o  "commitId\":.*," | cut -d "\"" -f 3 | cut -c1-7)
 #Check the commit id
 echo "$POD_ID vs $COMMIT"
 if [ "$POD_ID" == "$COMMIT" ] ;then
  echo "Deployment was successfuly updated with commitid : $COMMIT"
  echo "#####"
  echo "You can access the service with this URL: $POD_INGRESS:$POD_PORT"
  echo "#####"
  exit 0
 else
  echo "Deployment failed let's rollback!"
  kubectl -n "$NameSpace" rollout undo deployment $POD_NAME --to-revision=1
  kubectl -n "$NameSpace" rollout status deployment $POD_NAME -v4
  exit 1
 fi
else
echo "Checking pods commitid deployed with Ingress"
sleep 10
DNS_NAME=$(grep "host:" ingress.yml | cut -d ":" -f 2 | tr -d '[:space:]')
RUNNING_POD_NAME=$(kubectl -n "$NameSpace" get pods --sort-by='{.metadata.creationTimestamp}' | grep $POD_NAME | tail -1 | cut -d' ' -f 1)
POD_ID=$(kubectl -n "$NameSpace" exec -ti $RUNNING_POD_NAME -- wget -qO- http://localhost:$POD_PORT/monitoring/info | jq '.commitId' | tr -d "\"" | cut -c1-7)
 #Check the commit id
 echo "$POD_ID vs $COMMIT"
 if [ "$POD_ID" == "$COMMIT" ] ;then
  echo "Deployment was successfuly updated with commitid : $COMMIT"
  echo "#####"
  echo "You can access the service with this URL: $DNS_NAME"
  echo "#####"
  exit 0
 else
  echo "Deployment failed let's rollback!"
  kubectl -n "$NameSpace" rollout undo deployment $POD_NAME --to-revision=1
  kubectl -n "$NameSpace" rollout status deployment $POD_NAME -v4
  exit 1
 fi
fi
ENDSSH
