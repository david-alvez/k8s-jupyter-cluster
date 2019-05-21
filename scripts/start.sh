#!/bin/bash

jupyter notebook --ip=0.0.0.0 --NotebookApp.token='' &
ipcontroller --ip=$(hostname -i) --location=jupyter-iphyton-master --profile-dir=/home/jupyter/work/ --log-to-file --log-level=DEBUG
