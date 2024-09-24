---
layout: default
title: "Hey Siri, Turn On Gabbagool"
date: "2024/09/12"
---

> First-party source code for this post: [application](FIXME) and [Pulumi IaC](FIXME)
> Third-party source code for this post: [SoCo](FIXME) and [homebridge-http](FIXME)

I have some [Sonoses](FIXME). I subscribe to [Tidal](FIXME), where I maintain some personal playlists. I also love [SomaFM](FIXME). What I don't like is using my hands to listen to music. I want to queue up my Tidal playlist on my Sonos, or have it play a SomaFM station - by voice command.

Seems simple, right? It's 2024, that should be easy, right?

Sonos can be controlled by [its own voice command system](FIXME), or by Alexa, or with [Homekit](FIXME), AKA Siri, under certain conditions[FIXME: footnote like, you have really modern Sonosoes]. However, none of those options seem able to queue up a personal playlist - even if it's public. And all of those options play a weird version of SomaFM that has ads. SomaFM's [main deal is being ad-free](FIXME). That's why I love[FIXME: footnote and subscribe to] them.

As a computer programmer with a [home Kubernetes deployment platform](FIXME), I'm well positioned to get what I want.

What I want:

1. To play my personal Tidal playlist on my Sonos.
2. To play ad-free SomaFM on my Sonos.
3. To do the above through voice commands.
4. And by voice commands, I mean "Siri"[FIXME: footnote about Amazon] 

---

[I recently-ish deployed HomeBridge](FIXME) to my [home Kubernetes cluster](FIXME), and used the wonderful [homekit-http](FIXME) plugin to [bridge my espresso machine](FIXME) to HomeKit.

`homebridge-http` lets us easily configure "switches", published through HomeBridge, discoverable by HomeKit (and hence, Siri), which call arbitrary HTTP endpoints in response to HomeKit `on`, `off`, and `status` events. 

I'm already using it to control a device that really is a switch. But `homebridge-http` doesn't know or care about that - it just invokes HTTP endpoints in response to HomeKit events.

I also have my [daily chime job](FIXME) that plays a single sound file on my Sonoses at a particular time of day.

Can I leverage that existing, working infrastructure and application code to address my new requirements? Yes, I can! Code reuse! Wow!

---

What is the exact behavior that I want? I'll be honest, I was only able to answer this after retooling my prototype a few times, as I explored and discovered the behavior and characteristics of my system.

I eventually arrived upon:

1. First, [shuffle the playlist](FIXME). Truncate it to some arbitrary, relatively short length. How short? The [answer to the ultimate question of playlist length is 42](FIXME).
2. [Set volume level on the controller Sonos](FIXME). The controller is assigned by configuration (not discovery).
3. [Enqueue the playlist's first song on the controller. Start playback.](FIXME)
4. [Group all the other Sonoses to the controller.](FIXME)
5. [Enqueue the remaining 41 tracks.](FIXME)

This gives the best user experience. Music plays immediately. Next, music becomes multi-room. Finally, we prepare for the future - enqueing several more hours of music.

---

I ended up having to read [some of the SoCo code](FIXME) to understand why track titles were not showing up on the Sonos apps when I called [add_uri_to_queue()](FIXME) to otherwise successfully enqueue playable tracks. At first glance, it seems obvious: `title=""`. But it turns out, that's actually fine - that field is ignored. So where does Sonos  get the track title?

I used [Wireshark](FIXME) to inspect the [SOAP](FIXME) calls made by the [official Sonos app](FIXME), and discovered the true secret sauce is setting [DidlObject.desc](FIXME), which [SoCo never does](FIXME).

That knowledge in hand, I [rolled my own](add_uri_to_queue())[FIXME: footnote: resisting, in the interest of shipping, the urge to rewrite the whole app in Go/Rust, dispensing with the overhead of SoCo, and just sending SOAP fragments over the network], and now my track names show up as desired.

```python
def make_obj(self, track_id: int) -> DidlObject:
    """Returns a DidlObject for track_id."""
    # obtained via wireshark
    # unclear if the item_id prefix code actually matters. it might!
    item_id = f"10036028track/{track_id}"
    uri = f"x-sonos-http:track%2f{track_id}.flac?sid=174&amp;flags=24616&amp;sn=34"

    res = [DidlResource(uri=uri, protocol_info="x-rincon-playlist:*:*:*")]
    return DidlObject(
        # title is required but ignored, Sonos will fetch the title from the item_id
        resources=res, title="", parent_id="", item_id=item_id, desc=self.didl_desc
    )
```

---

Once my code was functionally correct, meaning, it grouped the several sonoses, set their volumes, enqueued the playlist portion, and started playback, it was time to optimize the experience. I do [as little as possible](FIXME) before starting playback - the whole point is to hear some music - then [spawn some threads](FIXME) to finish everything else.

Along the way, I discovered a couple of things. But before I talk about those, I have to talk about how I hooked this up to Siri.

---

# hooking it up to Siri

---

# challenges encountered 

I didn't root-cause farther than absolutely necessary. I don't really care whether it's HomeKit, HomeBridge, or even Kubernetes (it isn't) causing difficulties in my app. The solution is the same in any case.

First, HomeKit or HomeBridge has a short timeout. That makes sense: if you are turning on a lightbulb, you expect near instant response time, not a 3 minute wait. But grouping sonoses and enqueing even just 42 tracks takes a lot longer than turning on a lightbulb [FIXME: footnote at least, when using SoCo].

If my application doesn't respond promptly to the "on" request, Siri announces that it's taking a long time, which is reasonable and true. But it also distracts from the already-playing music, which is annoying.

The solution is to carefully structure the code to return HTTP 200 ASAP, and do the rest in the background.

```python
if source.kind == "playlists":
    if playlist := playlists.get(source.id, None):
        prepare_coordinator()               # ungroup and set volume
        playlist.play(coordinator)          # play the first song, start a thread to enqueue the rest 
        Thread(target=group_zones).start()  # start another thread to group the other Sonoses to the controller
        self.send_ok("ON")                  # homekit gets impatient, send OK ASAP
        return
```

Second, HomeKit, HomeBridge, or [homebridge-http](FIXME) sometimes sends two `on` messages to my backend in response to a user turning the "switch" on. So my app [ignores](FIXME) subsequent requests within a 1 minute window. Without that, the second request would interrupt the first one and enqueue a different playlist.

```python
if datetime.datetime.now() - last_on < datetime.timedelta(seconds=60):
    self.send_ok("ON")
    return

...

if playlist := playlists.get(source.id, None):
    last_on = datetime.datetime.now() # homekit/homebridge/homebridge-http sends two ON requests
...
```

Third, since there's no place for me to [join()](FIXME) the threads created by the [app](FIXME), I am concerned about resource leaks. For now, I can address (at least) memory leaks by applying [Kubernetes memory limits](FIXME) on the [deployment](FIXME). That won't solve other kinds of resource leaks, but if the other kinds show up, I can revisit the question. The memory limit is a simple, and possibly effective, first pass.

Since the app keeps no state (besides the one minute countdown to ignore duplicate "on" messages), it's safe to simply restart it if it runs out of memory.

Fourth, FIXME: make_sonos_server

```python
FIXME
```

Finally, and most relevant to the title of this post, Siri can get confused. Originally I named my playlist something like "mega playlist", and would say "Hey Siri turn on mega playlist". Instead of invoking my stuff, my phone would start playing something from Apple Music. A couple of times, it turned off my house lights in response to "Hey Siri turn on mega playlist".

So I gave my "switch" an unambiguous name. "Hey Siri turn on gabbagool" causes no confusion and works every time.

This entire architecture bypasses Siri (or Alexa, or whatever) trying to talk to my music service. I have never been able to get a voice assistant to play my personal playlists. With this application, I simply map my own names (like "gabbagool") to a [list of track ids](FIXME). No voice assistant needs to contact Tidal and get a playlist ID. I've simplified that out of the picture.

---

After accomplishing my original goals, I wanted to add another playlist. But I had neither the playlist ID (easy but tedious to get) nor the desire to write or [repurpose](FIXME) code to get the track ids.

Instead, I wrote a trivial script to [dump the track ids of the queue of a speific Sonos](FIXME). Then I just queued up all the songs in my playlist on to a Sonos, dumped them out, and added them to the [config file](FIXME). Easy peasy!

Adding the new playlist meant adding [a little more JSON](FIXME) to the [homebridge-http](FIXME) plugin's config in HomeBridge.

---

# key points

- Prototype to the point of flawed but complete functionality.
- Then optimize the pain points away.
- FIXME
- ... decoupled, modular design means i can swap out, for example, homebridge-http (or even homekit itself) and replace it with a more suitable voice interface. the business logic is fully contained in a small web app.
---


Mentions: 
x gabbagool
- dog nap
- make_sonos_server
- k8s/homeslice
x wireshark
- multiple prototypes to discern system behavior
x two homekit POSTs
x reading the homebridge-http source, not in my primary language but so what
- sonos discovery inside k8s
- latencies throughout
x optimizations: threading, order of ops, play ASAP. none premature! got it working first.
x SoCo lib
x dump_sonos_queue.py
- OSS-ing my soco change
