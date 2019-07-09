FROM ubuntu:18.04
ubuntu-minimal:bionic

ENV TZ=Europe/Berlin

RUN ssh-keygen -t rsa
RUN wget -c https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
RUN chmod +x Miniconda3-latest-Linux-x86_64.sh

https://insights.untapt.com/how-to-setup-an-ipython-parallel-cluster-on-google-compute-engine-august-2016-b2967a018547

https://github.com/jupyter/docker-stacks/blob/master/base-notebook/Dockerfile

https://ipyparallel.readthedocs.io/en/latest/

$ ./Miniconda2–4.1.11-Linux-x86_64.sh
$ # go through installation, say yes when asked to add to bash
$ source ~/.bashrc
$ conda install jupyter ipyparallel
$ ipython profile create --parallel --profile=default
$ ipcontroller --reuse --ip=*
$ # ctrl-c to quit

RUN apt-get install -y openjdk-8-jre wget jq telnet
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
