<pre>
This is a handy little trick that allows you to port forward traffic to a LoadBalancer typed service running in a Kubernetes playground on Katacoda.
Suppose the load balancer service, hellotherebye4now-service, is deployed on the K8s cluster as follows.

    controlplane $ kubectl get nodes -o wide
    NAME           STATUS   ROLES    AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION       CONTAINER-RUNTIME
    controlplane   Ready    master   35m   v1.18.0   172.17.0.20   <none>        Ubuntu 18.04.5 LTS   4.15.0-122-generic   docker://19.3.13
    node01         Ready    <none>   35m   v1.18.0   172.17.0.23   <none>        Ubuntu 18.04.5 LTS   4.15.0-122-generic   docker://19.3.13

    controlplane $ kubectl get svc
    NAME                        TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)        AGE
    hellotherebye4now-service   LoadBalancer   10.108.245.82   172.17.0.100   80:30194/TCP   7m52s
    kubernetes                  ClusterIP      10.96.0.1       <none>         443/TCP        34m
    controlplane $

These are the key steps to forward any external requests from a designated port, say 50080, on the controller to the LoadBalancer service, 172.17.0.100:80. The iptables commands are to be invoked on the controller. No, we don't lean on the NodePort type. All we want is just to test if the service works simply via plain, user-defined port forwarding configuration.

1.  Look for the KUBE-SVC-XXX NAT chain that kube-proxy uses to redirect the traffic bound for the load balancing VIP. Take note of the chain, KUBE-FW-PZQRGVAATKDHB3IH, afterward.

    controlplane $ iptables -t nat -L -n --line-numbers | grep 172.17.0.108
    3    KUBE-FW-PZQRGVAATKDHB3IH  tcp  --  0.0.0.0/0            172.17.0.100         /* default/hellotherebye4now-service:http loadbalancer IP*/ tcp dpt:80

2.  Insert a new nat rule at the top of the PREROUTING chain by "latching on to" to the above kube-proxy chain, KUBE-FW-PZQRGVAATKDHB3IH:

    controlplane $ iptables -t nat -I PREROUTING 1 -p tcp --dport 50080 -j KUBE-FW-PZQRGVAATKDHB3IH
    controlplane $ iptables -t nat -L PREROUTING
    Chain PREROUTING (policy ACCEPT)
    target     prot opt source               destination
    KUBE-FW-PZQRGVAATKDHB3IH  tcp  --  anywhere             anywhere             tcp dpt:50080
    KUBE-SERVICES  all  --  anywhere             anywhere             /* kubernetes service portals*/
    DOCKER     all  --  anywhere             anywhere             ADDRTYPE match dst-type LOCAL
    controlplane $


Now there you are. The LoadBalancer service is ready to be accessed via controller:50080 or 172.17.0.20:50080, e.g.
  node01 $ while true
    > do
    >   curl http://172.17.0.20:50080 2>/dev/null | grep -i hostname
    >   sleep 1
    > done
        <h3>My hostname is hellothere-deployment-557747b986-qtlw9</h3>
        <h3>My hostname is bye4now-deployment-7bc6b8bc9d-dgfd5</h3>
    ^C
    node01 $
</pre>    
