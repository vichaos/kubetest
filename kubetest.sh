#!/bin/sh
if [ "$#" -ne 1 ]; then
  echo "Usage: kubetest [network|dns]"
else
  if [ $1 = "network" ]; then
    echo "apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: overlaytest
spec:
  selector:
      matchLabels:
        name: overlaytest
  template:
    metadata:
      labels:
        name: overlaytest
    spec:
      tolerations:
      - operator: Exists
      containers:
      - image: busybox:1.28
        imagePullPolicy: Always
        name: alpine
        command: ["sh", "-c", "tail -f /dev/null"]
        terminationMessagePath: /dev/termination-log" | kubectl create -f - 
      sleep 20
  
      kubectl rollout status ds/overlaytest -w
  
      echo "=> Start network overlay test"
      kubectl get pods -l name=overlaytest -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.nodeName}{"\n"}{end}' | \
        while read spod shost
          do kubectl get pods -l name=overlaytest -o jsonpath='{range .items[*]}{@.status.podIP}{" "}{@.spec.nodeName}{"\n"}{end}' | \
            while read tip thost
            do kubectl --request-timeout='10s' exec $spod -- /bin/sh -c "ping -c2 $tip > /dev/null 2>&1"; RC=$?
              if [ $RC -ne 0 ]; then
                echo $shost cannot reach $thost
              else
                echo $shost can reach $thost
              fi
            done
          done
      echo "=> End network overlay test"
      kubectl delete ds/overlaytest
  elif [ $1 = "dns" ]; then
    echo "apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: dnstest
spec:
  selector:
      matchLabels:
        name: dnstest
  template:
    metadata:
      labels:
        name: dnstest
    spec:
      tolerations:
      - operator: Exists
      containers:
      - image: busybox:1.28
        imagePullPolicy: Always
        name: alpine
        command: ["sh", "-c", "tail -f /dev/null"]
        terminationMessagePath: /dev/termination-log" | kubectl create -f -
    sleep 10
    
    echo "=> Start checking local DNS"
    kubectl -n kube-system get pods -l dnstest --no-headers -o custom-columns=NAME:.metadata.name,HOSTIP:.spec.nodeName | \
      while read pod host
        do echo "Pod ${pod} on host ${host}"
          kubectl -n kube-system exec $pod -c kubedns cat /etc/resolv.conf
        done
    echo "=> End checking local DNS"
    
    export DOMAIN=kubernetes.default
    echo "=> Start resolving local domain - $DOMAIN"
    kubectl get pods -l name=dnstest --no-headers -o custom-columns=NAME:.metadata.name,HOSTIP:.spec.nodeName | \
      while read pod host
      do kubectl exec $pod -- /bin/sh -c "nslookup $DOMAIN > /dev/null 2>&1"; RC=$?
        if [ $RC -ne 0 ]
          then echo $host cannot resolve $DOMAIN
        else
          echo $host can resolve $DOMAIN
        fi
      done
    echo "=> End $DOMAIN"
    
    export DOMAIN=line.me
    echo "=> Start resolving external domain - $DOMAIN"
    kubectl get pods -l name=dnstest --no-headers -o custom-columns=NAME:.metadata.name,HOSTIP:.spec.nodeName | \
      while read pod host
      do kubectl exec $pod -- /bin/sh -c "nslookup $DOMAIN > /dev/null 2>&1"; RC=$?
        if [ $RC -ne 0 ]
          then echo $host cannot resolve $DOMAIN
        else
          echo $host can resolve $DOMAIN
        fi
      done
    echo "=> End $DOMAIN"
    
    export DOMAIN=baddomain
    echo "=> Start resolving bad domain - $DOMAIN"
    kubectl get pods -l name=dnstest --no-headers -o custom-columns=NAME:.metadata.name,HOSTIP:.spec.nodeName | \
      while read pod host
      do kubectl exec $pod -- /bin/sh -c "nslookup $DOMAIN > /dev/null 2>&1"; RC=$?
        if [ $RC -ne 0 ]
          then echo $host cannot resolve $DOMAIN
        fi
      done
    echo "=> End $DOMAIN"
    
    kubectl delete ds/dnstest
    
    echo "=> Start additional DNS resolver test";
    kubectl run -it --rm --restart=Never busybox --image=busybox:1.28 -- nslookup kubernetes.default
    kubectl run -it --rm --restart=Never busybox --image=busybox:1.28 -- nslookup www.google.com
    echo "=> End additional DNS resolver test";
  else
    echo "Usage: kubetest [network|dns]"
  fi
fi



