FROM jupyter/tensorflow-notebook:latest

USER root

RUN apt-get update && apt-get install -y \
    iputils-ping \
    net-tools \
    telnet

USER jovyan

RUN conda install --quiet --yes ipyparallel
