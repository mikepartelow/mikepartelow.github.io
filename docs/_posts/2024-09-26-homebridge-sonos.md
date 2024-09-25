---
layout: default
title: "Hey Siri, Turn On Gabbagool"
date: "2024/09/26"
publish: true
---

> First-party source code for this post: [application](https://github.com/mikepartelow/homeslice/tree/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos) and [Pulumi IaC](https://github.com/mikepartelow/homeslice/tree/a6197429a8007dcc72da1bcef5c339711d318552/pulumi/sonos)  
> Third-party source code for this post: [SoCo](https://github.com/SoCo/SoCo) and [homebridge-http](https://github.com/rudders/homebridge-http)

## What's the point?

I have some [Sonoses](https://www.sonos.com/en-us/home). I subscribe to [Tidal](https://tidal.com), where I maintain some personal playlists. I also love [SomaFM](https://somafm.com). What I don't like is using my hands to listen to music. I want to queue up my Tidal playlist on my Sonos, or have it play a SomaFM station - by voice command.

Seems simple, right? It's 2024, that should be easy, right?

Sonos can be controlled by [its own, quite excellent voice command system](https://www.sonos.com/en-us/sonos-voice-control), or by Alexa, or with [HomeKit](https://www.apple.com/home-app/), AKA Siri, under certain conditions[^sonos-siri]. However, none of those options seem able to queue up a personal playlist - even if it's public. And all of those options play a weird version of SomaFM that has ads. SomaFM's [main deal is being ad-free](https://somafm.com/support/).

[^sonos-siri]: if you have really modern Sonosoes

As a computer programmer with a [home Kubernetes deployment platform]({% post_url 2023-10-22-k8s-lightswitch %}), I'm well positioned to get what I want.

## Requirements

1. To play my personal Tidal playlist on my Sonos.
2. To play ad-free SomaFM on my Sonos.
3. To do the above through voice commands.
4. And by voice commands, I mean "Siri"

## Tools in hand

I recently-ish deployed HomeBridge to my home Kubernetes cluster, and used the wonderful [homebridge-http](https://github.com/rudders/homebridge-http) plugin to [bridge my espresso machine](https://github.com/mikepartelow/homeslice/tree/main/apps/lmz) to HomeKit.

`homebridge-http` lets users easily configure "switches", published through HomeBridge, discoverable by HomeKit (and hence, Siri), which call arbitrary HTTP endpoints in response to HomeKit `on`, `off`, and `status` events. 

I'm already using it to control a device that really is a switch. But `homebridge-http` doesn't know or care about that - it just invokes HTTP endpoints in response to HomeKit events.

I also wrote a [chime app](https://github.com/mikepartelow/homeslice/tree/main/apps/chime) that plays a single sound file on my Sonoses at a particular time of day, via a [Kubernetes Cronjob](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/pulumi/chime/chime.py#L108).

Can I leverage that existing, working infrastructure and application code to address my new requirements? Yes, I can! Code reuse! Wow!

## Refined Requirements

What is the exact behavior that I want? I was only able to answer this after retooling my prototype a few times, as I explored and discovered the behavior and characteristics of my system.

I eventually arrived upon:

1. First, [shuffle the playlist](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/lib/playlist.py#L57). Truncate it to some arbitrary, relatively short length. How short? The [answer to the ultimate question of playlist length is 42](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/sonos.py#L31).
2. [Set volume level on the controller Sonos](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/lib/server.py#L28). The controller is assigned by configuration (not discovery).
3. [Enqueue the playlist's first song on the controller. Start playback.](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/lib/playlist.py#L60)
4. [Group all the other Sonoses to the controller.](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/lib/server.py#L107)
5. [Enqueue the remaining 41 tracks.](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/lib/playlist.py#L74)

This gives the best user experience. Music plays immediately. Next, music becomes multi-room. Finally, we prepare for the future - enqueing several more hours of music.

## Getting it Done

I ended up getting to read some of the SoCo source code to understand why track titles were not showing up on the Sonos apps when I called [add_uri_to_queue()](https://github.com/SoCo/SoCo/blob/c41a10f74650d734170a465ceb5657ff5668d12b/soco/core.py#L2258) to otherwise successfully enqueue playable tracks. At first glance, it seems obvious: `title=""`. But it turns out, that's actually fine - that field is ignored. So where does Sonos  get the track title?

I used [Wireshark](https://www.wireshark.org) to inspect the [SOAP](https://www.w3schools.com/XML/xml_soap.asp) calls made by the [official Sonos app](https://support.sonos.com/en-us/downloads), and discovered the true secret sauce is setting [DidlObject.desc](https://github.com/SoCo/SoCo/blob/c41a10f74650d734170a465ceb5657ff5668d12b/soco/data_structures.py#L518C14-L518C18), which [add_uir_to_queue() does not do](https://github.com/SoCo/SoCo/blob/c41a10f74650d734170a465ceb5657ff5668d12b/soco/core.py#L2257).

That knowledge in hand, I [rolled my own add_uri_to_queue()](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/lib/playlist.py#L37), and now my track names show up as desired.

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

Once my code was functionally correct, meaning, it grouped the several sonoses, set their volumes, enqueued the playlist portion, and started playback, it was time to optimize the experience. I do [as little as possible](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/lib/playlist.py#L53) before starting playback - the whole point is to hear some music - then [spawn some threads](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/lib/playlist.py#L74) to finish everything else.

Along the way, I discovered a couple of things. But before I talk about those, I have to talk about how I hooked this up to Siri.

## Hooking it Up to Siri

FIXME  
FIXME  
FIXME  

---

## Challenges Encountered 

In all cases, I didn't root-cause farther than absolutely necessary. I don't really care whether it's HomeKit, HomeBridge, or even Kubernetes (it isn't) causing difficulties in my app. The solution is the same in any case - fix my app, because I'm not going to fix HomeKit, HomeBridge, or Kubernetes (not that I'd need to).

### Timeouts

HomeKit or HomeBridge has a short timeout. That makes sense: if you are turning on a lightbulb, you expect near instant response time, not a 3 minute wait. But grouping Sonoses and enqueing even just 42 tracks takes a lot longer than turning on a lightbulb.

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

### I may have committed some light idempotency

HomeKit, HomeBridge, or homebridge-http sometimes sends two `on` messages to my backend in response to a user turning the "switch" on. So my app ignores subsequent requests within a 1 minute window. Without that, the second request would interrupt the first one and enqueue a different playlist.

```python
if datetime.datetime.now() - last_on < datetime.timedelta(seconds=60):
    self.send_ok("ON")
    return

...

if playlist := playlists.get(source.id, None):
    last_on = datetime.datetime.now() # homekit/homebridge/homebridge-http sends two ON requests
...
```

### Class Factory

FIXME: make_sonos_server

```python
FIXME
```

### Device Discovery

[SoCo](FIXME) relies heavily on device discovery, that is, discovering Sonos player IP addresses by broadcasting "show yourself!!!" messages on the network and waiting for players to self-report. The assumption that this will work is baked heavily into the SoCo library, but it doesn't work well from within Kubernetes. [It can be made to work](https://serverfault.com/a/948778), probably, but a simpler approach is to simply obtain player IPs [FIXME: footnote: in my case, I configure my DHCP server to assign fixed IPs to my players, so hardcoding works fine] and pass them as inputs to the application.

I previously ran into this problem when writing [chime](FIXME), where resolving it would have been even more difficult, since in that case, the application is run as a [Cronjob](FIXME), making NodePort assignment more difficult.

### Gabbagool

Finally, and most relevant to the title of this post, Siri can get confused. Originally I named my playlist something like "mega playlist", and would say "Hey Siri turn on mega playlist". Instead of invoking my stuff, my phone would start playing something from Apple Music. A couple of times, it turned off my house lights in response to "Hey Siri turn on mega playlist".

So I gave my "switch" an unambiguous name. "Hey Siri turn on gabbagool" causes no confusion and works every time.

This entire architecture bypasses Siri (or Alexa, or whatever) trying to talk to my music service. I have never been able to get a voice assistant to play my personal playlists. With this application, I simply map my own names (like "gabbagool") to a [list of track IDs](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/config/config.yaml). No voice assistant needs to contact Tidal and get a playlist ID. I've simplified that out of the picture.

### Another Playlist

After accomplishing my original goals, I wanted to add another playlist. But I had neither the playlist ID (easy but tedious to get) nor the desire to write or [repurpose](https://github.com/mikepartelow/homeslice/blob/main/apps/backup-tidal/backup_tidal.py) code to get the track IDs.

Instead, I wrote a trivial script to [dump the track IDs of the queue of a speific Sonos](https://github.com/mikepartelow/homeslice/blob/main/apps/sonos/dump_sonos_queue.py). Then I just queued up all the songs in my playlist on to a Sonos, dumped them out, and added them to the [config file](https://github.com/mikepartelow/homeslice/blob/a6197429a8007dcc72da1bcef5c339711d318552/apps/sonos/config/config.yaml#L3353). Easy peasy!

## The Catch

There's one problem here. I've crammed my playlist into a "switch", but it's not a switch. There's no unambiguous way to check status - even if the Sonoses are playing, are they playing the playlist I "turned on", or something else I added later? What if I changed the queue after "turning on" the playlist, what's the "status" then?

Likewise, there is no way to turn it "off". What's "off" mean here? Pause playback? What if I manually changed the groups or the playing music, what's "off" mean there?

This incoherency is the price I pay for shoehorning something that is definitely not a "switch" into a switch-like interface. That said, I got 90% of what I want, after a few hours of work, and I can live with the incoherency. If it bothers me too much, I can look for a different HomeBridge plugin, or simply define what "status" and "off" mean to me.

## Key Points

- Prototype to the point of flawed but complete functionality.
- Then optimize the pain points away.
- Accept acceptable incoherence to ship quickly.
- Use a decoupled, modular design to enable resolution of incoherence, later, if desired.
