---
layout: default
title: "My lightswitch crashed so I added two nodes to my single node Kubernetes cluster"
date: "2024/09/13"
---

## Background

I set up a single-node [microk8s](FIXME) Kubernetes cluster to manage my [lightswitch]({% post_url 2023-10-22-k8s-lightswitch %}) and other [home automation tasks](FIXME).

That same host also ran a few non-k8s workloads, like the controller for my home networking system.

On August 26, I received an extra PC that I planned to use as a redundant mirror of my single-node cluster. The idea was that if the primary failed, I could simply change the IP address on the secondary to match the IP address of the old, failed primary, and all the devices around the house would notice no difference and keep on humming.

It turns out that was a reasonably good DR plan!

On August 28, two days after I got the secondary PC, the primary suffered an unidentified catastrophic failure and would not boot. I had not yet begun the mirroring process. Yikes!

## Recovery

Despite not having set up the secondary PC yet, I was able to quickly recover most of my services. I followed a modified version of my original DR plan. On a fresh Linux install, I configured the new PC to have the old PC's IP address. I followed public instructions and private notes for setting up the network controller software. 

I had a backup of my network controller config, although it was old enough that it did not include my new edge router. 

My custom applications - [homeslice](FIXME) - were trivial to reinstall: a single `pulumi up` was all it took. [IAC](FIXME) is a powerful ally!

The tricky part was configuring the microk8s container registry the way I needed it. Public documentation of my exact config is not available, and my notes weren't great. Fortunately, someone [blogged about](FIXME) the exact process - me! Following my own instructions, I finished up my recovery.

I had most of everything back up and running within a few distracted evening hours. [homeslice](FIXME), by design, hardcodes some IP addresses, for light bulbs and so forth. After provisioning the new network controller, some devices got new IP addresses. The fix was simply to change the config and run `pulumi up` again.

## Root Cause

After mitigating the outage, I moved on to [RCA](FIXME). I obtained an SSD enclosure and a new SSD. The new SSD was recognized by the failed PC, and the failed PC's original SSD, in the enclosure, was not readable. Mystery solved: SSD failure.

I put the new SSD in the old PC. Now I had two fully functional PCs, as originally planned. At this point, I admitted my true desire: a 3 node high-availability Kubernetes cluster. For my lightswitch.

I put in the order for a 3rd PC and spent the order processing time thinking about what I could do to make the next outage recoverable in minutes instead of hours.

## What went well

- My custom apps were all managed in Pulumi IAC, and were fully redeployable with a single `pulumi up` (with the exception of the [chime](FIXME) [PVC](FIXME) mp3).
- My custom apps produce docker images hosted on [ghcr.io](FIXME), so disaster recovery was not blocked on getting my local container registry working.
- The network controller software install process is publicly documented.
- I had backups of my [Homebridge](FIXME ?) config and my network controller config.
- I had migrated all custom apps from various local, dockerized, or cron based scripts to k8s primitives managed with IAC. There was nothing of value on the microk8s host running *outside* of Kubernetes.

## What went poorly

- My backups were a bit old
- My backups were not all in one place, I had to go hunting
- Since my network controller was hosted on the PC that crashed, I was not able to use the network controller (it was down!) to assign a DHCP IP address to the new PC's MAC address. I had to learn "how we do it this week" in Linux. It seems like every time I need to configure a static IP (which is not often), the Linux world has invented a new way to do it.

## Where I got lucky

- I had a fresh, working PC on hand, ready to go, just two days old!
- I had working backups of all the things that could be recovered from backups
- Although my network controller backup was pretty old, it worked with the latest version of the software

## Proper Disaster Recovery

I can imagine two DR scenarios.

### Single-node k8s cluster

If a single node cluster fails, recovery is straightforward and looks a lot like what I did:

- Repair or replace the busted node
- Run a script that installs all Kubernetes prerequisites (like microk8s) and all non-Kubernetes software (the network controller)
- Set static IP (looking up how we do it this year)
- Restore network controller config from backup (manually)
- Obtain Kubernetes host config
- `pulumi up` to reinstall my apps [FIXME: footnote: until I have the pulumi operator working]
- Restore homebridge config from backup (manually)


### Multi-node k8s cluster

A multi-node cluster of sufficient size (>= 3 nodes) should self-heal.  

If the failed node isn't the one running the network controller, there's no urgency to do anything. Just repair or replace the failed node, eventually. That may require installing and configuring microk8s.

If the failed node **is** the one running the network controller, then recovery involves:

- Install network controller on a working node
- Set that node's static IP address to the address of the failed node, the address expected by my IoT devices.

### That network controller...

In either scenario, the network controller is unavailable to manage DHCP assignments, so I have to set static IP addresses however that's done in the node's OS.

### Those manual steps...

Both scenarios involve a lot of manual steps. If I lose my notes, or if the process for any of the steps changes, my next disaster recovery won't go smoothly.

## One plan to rule them all

I chose [Ansible](FIXME) instead of "a script". I've never used it before, but it was straightforward to get some working [playbooks](FIXME) that install the network controller, microk8s, set static IPs, and perform the steps necessary to get microk8s working with my local container registry.

I tested it out on clusters of [multipass](FIXME) VMs, then ran it against my other two nodes. I manually joined them to the primary, and then things started failing again!

### False start

When my cluster had just one node, I could use the [hostpath-storage](FIXME) plugin. With multiple nodes, that *could* work, with a lot of headache. I decided to postpone multi-node and focus on perfecting my Ansible playbook and my backup jobs. Later I returned to the problem, and learned that [OpenEBS](FIXME) is essentially a drop-in replacement for `hostpath-storage` (in my setup), and now I have everything I wanted: a [working Ansible playbook](FIXME), [automated network controller backups](FIXME), and a multi-node microk8s cluster in [HA mode](FIXME).


### Avoiding bitrot

Scripts go out of date over time, including Ansible playbooks and Pulumi programs. Declarative IaC makes it easy to avoid surprises in a DR scenario. By design, declarative IaC is idempotent - you can apply your IaC repeatedly, and if there are no changes, it has no effect.

So the key to detecting mismatches between your IaC and the capabilities of the underlying infrastructure (new way to set static IP addresses, fresh untracked dependencies, etc.) is to apply your IaC periodically and fix what's broken.

I can use my Ansible playbooks to perform OS upgrades, Microk8s upgrades, and to upgrade the network controller. This way, I have both a test of the current validity of my IaC, and my IaC stays current with my infrastructure.

I also learned about the brilliant [multipass](FIXME), and can use that (maybe even in an automation) to continuously validate my IaC and develop fixes.


## A brighter future

The way to deal with setbacks is to come back stronger than before. That's exactly what I did here. Now I have:

- [Automated network controllers backups](FIXME).
- [Ansible](FIXME) IaC to rapidly provision new nodes and new network controller hosts.
- 3 nodes in my k8s cluster
- Pulumi code that I know for sure can restore a cluster from scratch.

## Still to do

The failed SSD was about 5 years old. It may have died due to excessive writes from logging, particularly once I installed Kubernetes on it. I'd like to reduce excessive logging to prolong SSD life on all my nodes.

I'd also like to eliminate the few remaining manual steps, like Homebridge backup, running `pulumi up` manually, and manual periodic k8s/os upgrades.

Monitoring may have been useful here, I may have noticed a decline in write speeds or an increase in write errors. But honestly, I don't really want 3AM alerts from my lightswitch. And even if I had gotten some advance notice of the failure, I still would have had to run a DR playbook - and now I have a good one!

## Wrapping up: the importance of colleagues

A lot of this is similar to what I do at my day job, although the specific tech, the scale, and the levels of abstraction differ.

The important thing here is the mindset: *when problems strike, mitigate them, then ensure they never happen again*.

That's been my ideal forever, but there is no substitute for surrounding yourself with like-minded people who inspire you to fully live up to your ideals.
