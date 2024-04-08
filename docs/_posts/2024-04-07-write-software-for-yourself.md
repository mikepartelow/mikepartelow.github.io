---
layout: default
title: "Write Software For Yourself"
date: "2024/04/07"
---

## What?

I wrote a [Python program](https://github.com/mikepartelow/homeslice/blob/59822ba52a4052941890f0220ba9158a20250c7a/apps/backup-tidal/backup_tidal.py) to download a Tidal playlist, encode it as JSON, and push it to a Git repository.

It runs as a [Kubernetes Cronjob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) on my [home Kubernetes cluster](({% post_url 2023-10-22-k8s-lightswitch %})).

Originally conceived as a hedge against vendor lock-in, some good design choices led to unplanned but supported use cases - that's why I am comfortable characterizing the original design choices as "good".

The playlist I backup has 3000+ songs, and I append to it often. Tidal's user interface isn't designed for answering the question "what was the third to last song I added to my 3000+ entry playlist?". Even if it was good at that, I don't want to invest time learning how to use their UI, since they're likely to change it and I am likely to switch to a different service[^for-example].

But a pretty-printed JSON file pushed periodically to GitHub? I am very willing to invest time practicing with GitHub's interface, and it's quite good at diffing JSON. I can answer lots of questions about my playlist very easily, without writing code or learning another half-baked interface-of-the-week.

## So?

Don't wait for a genius idea to arrive, write code that does something moderately useful. Designed well, you will find additional uses later on, and odds are good you'll learn something valuable - or, even better, produce reference code for yourself - along the way.

Eventually, when I decide to migrate to another music service, I will already have an up-to-date export of my playlist. And before then, if I want, I could build my own suggestion engine based on my musical tastes. Sky's the limit.

And I have custom reference Python code for dealing with Git repos (useful!) and Tidal (much less useful!), plus the Kubernetes deployment side of things (very useful!).

---

[^for-example]: For example, if Tidal decides my playlist is their property and makes it impossible for me to obtain a copy.
