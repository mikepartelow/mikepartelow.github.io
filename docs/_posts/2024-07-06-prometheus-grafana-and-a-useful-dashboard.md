---
layout: default
title: "Prometheus, Grafana, and a Useful Dashboard (for homeslice)"
date: "2024/07/06"
---

## Background

> All source code for this post can be found [here](https://github.com/mikepartelow/homeslice)

Last year I [moved my custom home automation to a literally in-house Kubernetes cluster]({% post_url 2023-10-22-k8s-lightswitch %}).

There were many immediate benefits, but one long-term goal was to add monitoring, dashboards, and maybe alerts. 

A good dashboard quickly answers the question "is something wrong?". A great dashboard points directly at the root of the problem. Both require quality metrics.

Hosting applications on Kubernetes, particularly if we design them specifically to run on Kubernetes (e.g. using Kubernetes Cronjobs for recurring tasks, versus in-app constructs like "background jobs"), means we can leverage open source metric exporters like [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics).

## What problem are we trying to solve?

I have a number of Kubernetes Cronjobs that automate various [important]({% post_url 2024-04-07-write-software-for-yourself %}) [things]({% post_url 2023-11-05-k8s-chime %}). I'd like to know when/if any of those jobs fail to run. 

In the case of the chime, it's fairly obvious - I don't hear the chime that day, assuming I'm home at the time and paying attention.

In the case of the backups, I'd have to go check individual Github repos, or review my jobs in `kubectl` or `k9s`.

Instead of that, I'd like to look at a dashboard of all my cronjobs and have the dashboard point out if anything failed to run.

## What's the simplest approach?

The simplest approach is an all-in-one package like [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator?tab=readme-ov-file#prometheus-operator), installing a full monitoring and dashboarding stack in one shot.

The next simplest approach is the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) Helm Chart, which does basically the same thing as the Operator, but differently.

I chose the third simplest approach, installing [Prometheus](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus) and [Grafana](https://github.com/grafana/helm-charts/tree/main/charts/grafana) from their own separate Helm Charts. 

I believe this choice gave me the best balance of simplicity, ease of maintenance, and learning.

## Pulumi

My IaC platform is Pulumi. Pulumi offers two ways to install Helm charts: a [Chart](https://www.pulumi.com/registry/packages/kubernetes/api-docs/helm/v4/chart/) Resource, or a [Release](https://www.pulumi.com/registry/packages/kubernetes/api-docs/helm/v3/release/) Resource.

I used Pulumi's handy [guide](https://www.pulumi.com/registry/packages/kubernetes/how-to-guides/choosing-the-right-helm-resource-for-your-use-case/) and chose a `Release`, since I fall under their very first use case: *Fire-and-forget*.

It worked out well!

### Challenges

#### Ingress confguration

Both charts required a little bit of customization to support mounting their Ingress URLs at subpaths. I want to navigate to `http://my-homelab/prometheus` and `http://my-homelab/grafana`. 

I configured the Ingress in both helm charts to rewrite URLs.

- [Prometheus Values](https://github.com/mikepartelow/homeslice/blob/5f30888a2ff898a5ad43a425208bb2c715777ef9/pulumi/monitoring/prometheus.py#L33)
- [Grafana Values](https://github.com/mikepartelow/homeslice/blob/5f30888a2ff898a5ad43a425208bb2c715777ef9/pulumi/monitoring/grafana.py#L31)

```python
"ingress": {
    "enabled": True,
    "ingressClassName": "public",
    "annotations": {
        "nginx.ingress.kubernetes.io/rewrite-target": "/$2",
    },
    "path": "/grafana(/|$)(.*)",
    "hosts": [""],
}
```

I also configured both Prometheus and Grafana to recognize they were serving from a subpath - something I was not able to cleanly configure for other apps that weren't built cloud-native, like Homebridge.

- [Prometheus](https://github.com/mikepartelow/homeslice/blob/5f30888a2ff898a5ad43a425208bb2c715777ef9/pulumi/monitoring/prometheus.py#L30)
- [Grafana](https://github.com/mikepartelow/homeslice/blob/5f30888a2ff898a5ad43a425208bb2c715777ef9/pulumi/monitoring/grafana.py#L78)

#### Datasource URL

Grafana needs to know where to find Prometheus. I expected I could use a Kubernetes [internal DNS name](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) as I do [elsewhere in my cluster](https://github.com/mikepartelow/homeslice/blob/main/pulumi/Pulumi.prod.yaml#L17). But for reasons unknown (I suspect some configuration issue in the Grafana pods), that didn't work. Using a [non-FQDN](https://github.com/mikepartelow/homeslice/blob/5f30888a2ff898a5ad43a425208bb2c715777ef9/pulumi/Pulumi.prod.yaml#L45) worked, though, so I went with that and can dig deeper later.

I suspect that using the Operator or `kube-prometheus-stack` would have resolved this issue for me, but it's more of a mystery than a blocker, so I'm happy with how things turned out.

### Rolling it out

Once I'd gotten the Helm charts configured, deployment was as simple as `pulumi up`. Then I could navigate my browser to `http://my-homelab/prometheus` and see some metrics!

![prometheus](/assets/img/prometheus.png)

Likewise, `http://my-homelab/grafana` renders friendly old Grafana, hooked up to my Prometheus instance and all the mertics exported by `kube-state-metrics` and `node-exporters` - all without me instrumenting any of my application code.

Time to build a dashboard!
