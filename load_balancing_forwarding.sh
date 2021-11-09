#!/bin/bash

if [ -z "$1" ]
then
  myservice="hellotherebye4now-service"
else
  myservice=$1
fi

if [ -z "$2" ]
then
  myport="50080"
else
  myport=$2
fi

lbip=`kubectl get svc $myservice -o=jsonpath='{.status.loadBalancer.ingress[0].ip}'`
lbchain=`lbchain=`iptables -t nat -L -n | grep $lbip | awk '{print awk $1}'``

if [ -n "$lbip" ] && [ -n "$lbchain" ]
then
  iptables -t nat -I PREROUTING 1 -p tcp --dport $myport -j $lbchain
fi
