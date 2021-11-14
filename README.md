<pre>
Actually, we can do one better by latching on directly to the KUBE-SVC chain for a Cluster-IP service.

1. Suppose quick-web is deployed only as a Cluster-IP type service to start with.

controlplane $ kubectl get nodes -o wide
NAME           STATUS   ROLES    AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION       CONTAINER-RUNTIME
controlplane   Ready    master   28m   v1.18.0   172.17.0.26   <none>        Ubuntu 18.04.5 LTS   4.15.0-122-generic   docker://19.3.13
node01         Ready    <none>   28m   v1.18.0   172.17.0.28   <none>        Ubuntu 18.04.5 LTS   4.15.0-122-generic   docker://19.3.13
controlplane $ 
controlplane $ kubectl get svc
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   4m8s
quickweb     ClusterIP   10.110.189.12   <none>        80/TCP    87s
controlplane $

2.  The Cluster-IP service is handled by kube-proxy through the KUBE-SVC-F5B3UGH2MHZEGIUL sub-chain.

controlplane $ iptables -t nat -L | grep -i KUBE-SVC | grep 10.110.189.12
KUBE-SVC-F5B3UGH2MHZEGIUL  tcp  --  anywhere             10.110.189.12        /* default/quickweb: cluster IP */ tcp dpt:http

3. Install ECMP routes towards a publicly accessible load balancing VIP via the K8s nodes. The routes are installed on a last hop or edge router in front of the K8s cluster. Assume the router is running Linux in this example.

edge-router $ ip route add 192.168.25.100/32 \
> nexthop via 172.17.0.26 weight 10
> nexthop via 172.17.0.28 weight 10

edge-router $ ip route
default via 172.17.0.1 dev ens3
10.244.0.0/24 via 172.17.0.26 dev ens3
10.244.1.0/24 dev cni0 proto kernel scope link src 10.244.1.1
172.17.0.0/16 dev ens3 proto kernel scope link src 172.17.0.28
172.18.0.0/24 dev docker0 proto kernel scope link src 172.18.0.1 linkdown
192.168.25.100 via 172.17.0.26 dev ens3
node01 $

4. Insert a new NAT rule into PREROUTING Chain by latching on to the existing KUBE-SVC-F5B3UGH2MHZEGIUL sub-chain.

controlplane $ iptables -t nat -I PREROUTING 1 -p tcp -d 192.168.25.100 --dport 80 -j KUBE-SVC-F5B3UGH2MHZEGIUL
controlplane $
controlplane $ iptables -t nat -L PREROUTING -n --line-numbers
Chain PREROUTING (policy ACCEPT)
num  target     prot opt source               destination
1    KUBE-SVC-F5B3UGH2MHZEGIUL  tcp  --  0.0.0.0/0            192.168.25.100       tcp dpt:80
2    KUBE-SERVICES  all  --  0.0.0.0/0            0.0.0.0/0            /* kubernetes service portals */
3    DOCKER     all  --  0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL
controlplane $

5. Voila! The same Cluster-IP service is now accessible to an external node via the VIP URL.

external-node $ curl http://192.168.25.100
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h3>Welcome to nginx!</h3>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
external-node $ 

---
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

(1) Look for the KUBE-FW-XXX NAT chain that kube-proxy uses to redirect the traffic bound for the load balancing VIP. Take note of the chain, KUBE-FW-PZQRGVAATKDHB3IH, afterward.

    controlplane $ iptables -t nat -L -n --line-numbers | grep 172.17.0.100
    3    KUBE-FW-PZQRGVAATKDHB3IH  tcp  --  0.0.0.0/0            172.17.0.100         /* default/hellotherebye4now-service:http loadbalancer IP*/ tcp dpt:80

(2) Insert a new nat rule at the top of the PREROUTING chain by "latching on to" to the above kube-proxy chain, KUBE-FW-PZQRGVAATKDHB3IH:

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
        <h4> My hostname is hellothere-deployment-557747b986-qtlw9 </h4>
        <h4> My hostname is bye4now-deployment-7bc6b8bc9d-dgfd5 </h4>
    ^C
    node01 $

</pre>
