#!/bin/bash

PODS=$1

kubectl scale deployment/jupyter-iphyton-node --replicas=$PODS
