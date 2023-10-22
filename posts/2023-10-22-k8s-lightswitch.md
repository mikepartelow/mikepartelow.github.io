# My lightswitch was slow so I ported it to Kubernetes

**2023/10/22**

I've got a boring old dumb-lamp that isn't anywhere near a switched outlet. 

![Dumb-Lamp Off](../img/k8s-lamp-off.jpeg)

 I've also got a hella rad light switch on the other side of the room.
 
![hella rad light switch](../img/k8s-switch.jpeg). 
 
 Wouldn't it be great if I could use the switch to turn on the light?

I solved that years ago by plugging the dumb lamp into a smart switch, plugging the hella rad light switch into an IoT device, programming the IoT device to make a REST API call to a low power PC on my local network, and coding a Python API server to make an API call to the smart switch. 

Finally, I could turn on my dumb lamp with my hella rad switch, from the other side of the room! An emergent property of this system was a 5-20 second delay between flipping the hella rad switch and the dumb light toggling on or off, conveniently allowing ample time to exit the room before darkness falls.

Eventually the API server made it into a Docker container, and grew a bunch of orthogonal features, like powering a button-activated bedside clock and a momentary push-button switch  bedroom lamp and some smart speaker integrations to play custom chimes at important points throughout the day.

In October 2023, I installed [Kubernetes](http://kubernetes.io) on the low power PC and refactored my single-container Python app [homeslice](https://github.com/mikepartelow/homeslice) into Go microservices managed by [Pulumi](https://www.pulumi.com). Here's how that went!

# Application Code

Here's the code for the application I deployed to my home cluster: [homeslice](https://github.com/mikepartelow/homeslice). More about this later.

# Installing Kubernetes

I have one node, which is a slightly smaller cluster than I'm used to professionally. For my needs, [microk8s](http://microk8s.io) seemed like a reasonable choice. Now that I've used it for a bit, I'm happy with my decision. 

microk8s documentation is geared toward local development, but I wanted to develop on my laptop and deploy to microk8s on another host.

## registry.localdomain

microk8s ships with a container registry plugin. You can push your containers to the registry at its default port `32000`, and refer to them in your k8s config as `localhost:32000/image-name`. Since I'm developing and building on my laptop, pushing to `localhost` isn't going to work.

I added an entry for `registry.localdomain` to both my laptop's `/etc/hosts` and the same file on each (one) of the nodes in my Kubernetes cluster, resolving to my microk8s host. 

I added the following to my laptop's docker config:

```json
  "insecure-registries": [
    "registry.localdomain:32000"
  ]
```

Then I followed [these instructions](https://microk8s.io/docs/registry-private) to get microk8s pulling from its own registry, using the name `registry.localdomain`.

Now I can tag my images on my laptop, push them to my microk8s registry, and refer to them in Pulumi by the same tag I used to push.

## kubectl

I configured my laptop's kubectl [as documented here](https://microk8s.io/docs/working-with-kubectl).

# Microservices

After that, I had a nicely working Kubernetes cluster inefficiently doing absolutely nothing. How aobut deploying some containers?

The old [homeslice](https://github.com/mikepartelow/homeslice) code was a Python Flask monolith serving endpoints under `/api/v0/` from a single Docker container. The container included several Python libraries to deal with different branded smart switches, and an Sqlite database to preserve the state of the custom smart buttons/switches I built around the home. 

My smart buttons and switches aren't much fun to program. Maybe the IoT build ecosystem has progressed since I created them, but for this project, I decided to leave them be and just reimplement the endpoints they're already hitting.

## Switches

[https://github.com/mikepartelow/homeslice/tree/main/apps/switches](source code)

Originally I used the wonderfully named [ouimeaux](https://github.com/iancmcc/ouimeaux) to communicate with my Wemo brand smart switches. During this project, I discovered ouimeaux had been abandoned and replaced by a [simple Python script](https://github.com/iancmcc/ouimeaux/blob/develop/client.py). 

I don't need device discovery, I already know my device's IP addresses. The on/off/toggle logic is trivial, and who wants unnecessary Python dependencies in their Go project? I ported the bits I needed to Go. 

## Clocktime

[https://github.com/mikepartelow/homeslice/tree/main/apps/clocktime](source code)

I built a few custom smart clocks around the home so I wouldn't have to change the time for [DST](https://www.wired.com/story/2023-daylight-saving-time/). It's easier to make changes to my APIs than to my IoT devices, so I keep my IoT code as simple as possible, implementing all the logic on the server side. 

By "all the logic" I mean figuring out what time it is in my timezone and returning that from an API. 

`/api/v0/clocktime` checks the hosts's current time, converts it to my timezone, and returns `%H%M` as `Content-Type: text/plain`. The IoT clock displays what the endpoint returns. Simple! 

I could move to a different continent and not need to update my IoT clock's code. I could move to [Jupiter](https://spaceplace.nasa.gov/days/en/) and as long as my API server could find an NTP server, my IoT clock wouldn't need an update. Perfect.

I'd need some updates to get things working on Venus, my clock's display isn't wide enough for that many digits. Something to keep in mind.

## Buttons

[https://github.com/mikepartelow/homeslice/tree/main/apps/buttons](source code)

I have various IoT smart buttons around the home. When pressed, they report their state to my API, which can then be queried by other interested devices at `/api/v0/buttons`. The old [homeslice](https://github.com/mikepartelow/homeslice) recorded state in an Sqlite database. 

At some point I will add a Postgres instance to my Kubernetes cluster, but for the initial port, I used an [LRU cache](https://github.com/hashicorp/golang-lru) to remember button states for a while. 

The poor UX of the buttons has always been a major part of their charm, the excitement of potential cache eviction just elevates the whole experience of pressing a button in my home.

### Buttontimes

To minimize complexity on my button-activated smart clock, I added an `/api/v0/buttontimes` endpoint that reports the state of a button and the current time in one API call. The `buttons` microservice calls the `clocktime` endpoint to fetch the current time.

# Make

[https://github.com/mikepartelow/homeslice/tree/main/apps/Makefile](source code)

Mmm, build systems. I wanted to focus on Kubernetes for this project so I stuck with what I know, which unfortunately is `make`. I wanted to be able to run `make` from 3 places: the top level of my project, within each microservice directory, and inside the locally running containers. Why that last one?

My laptop is Apple Silicon, and my Kubernetes cluster (ha ha) is Intel, so the containers I push to my registry are built for Intel, which is relatively slow to build on Apple Silicon. For local debugging it's convenient to build native containers, and build my Go code inside them to keep a tight dev loop.

I know what you're thinking: I should deploy a CI/CD system to my Kubernetes cluster and build my native containers there. I like the way you think, friend.

# Pulumi

[https://github.com/mikepartelow/homeslice/tree/main/pulumi](source code)

I used Pulumi to manage deploying my application. It's great. 

I don't want to publish my IP addresses to Github, and managing my deployments in Pulumi makes that very easy.

# The Bottom Line

At the end of it all, what did I accomplish? 

![Dumb-Lamp On](../img/k8s-lamp-on.jpeg)

Unexpectedly, my lightswitch now behaves almost like a real lightswitch, with a near instantaneous activation time. 

That's right, I optimized my lightswitch by porting it to Kubernetes. It's a little sad, and a little dangerous/thrilling: now the room gets dark before I have time to leave. It's a big change to my lifestyle.

Installing microk8s was incredibly easy. You could even say it was a [snap](https://microk8s.io/docs/getting-started), I know I sure said that. A lot.

Kubernetes is an amazing platform for deploying applications, even trivial ones in a home setting. I can use the same [homeslice](https://github.com/mikepartelow/homeslice) repo to deploy my app to AWS or to a RaspberryPi. 

Importantly for me, it removes a barrier to home tinkering. Now I have a platform that is fun and easy to deploy to, and I can build out microservices instead of bolting stuff on to a brittle old Docker container full of abandoned Python libraries or editing `/etc/crontab` on my API server for my daily chimes.

I had this idea that Kubernetes was too "heavy duty" for a single node deployment. That turns out to be incorrect, and to the extent that Kubernetes was tricky to setup in a home environment, it's a one-time cost that's already paid. 

Designing apps to run in Kubernetes imposes - or at least strongly encourages - best practices that are easy to ignore when deploying to a single container.

Along the way I went down a couple rabbit holes, like working with [coredns](http://coredns.io) before realizing that wasn't how to solve my image tag hostname problem. Now I know a bit about coredns. Whoops!

Thanks for reading!
