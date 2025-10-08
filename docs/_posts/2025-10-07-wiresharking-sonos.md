---
layout: default
title: "Wiresharking Sonos"
date: "2025/09/07"
publish: true
---

## Frustration is the Mother of all Wiresharking

I've got a bunch of [Sonos](http://sonos.com) speakers in a multi-room configuration. I use [Tidal](http://tidal.com) as my main music service. I often get (seemingly) random dropouts while playing Tidal on Sonos. One or two speakers go silent for about 20-60 seconds while the others keep playing. This post isn't about that[^1]. 

[^1]: My investigation into the dropouts may get its own post (clue: I don't ever experience dropouts when streaming SomaFM).

I'm auditioning [Apple Music](https://www.apple.com/lae/apple-music/) to replace Tidal. This post isn't that, either. 

This post is about how I'll update my [Homekit-activated](https://github.com/mikepartelow/homeslice/blob/main/apps/gosonos/README.md) [Homebridge-bridged](https://github.com/mikepartelow/homeslice/tree/main/pulumi/homebridge) [Kubernetes-hosted](https://github.com/mikepartelow/homeslice/tree/main/pulumi/sonos) [Go service](https://github.com/mikepartelow/homeslice/tree/main/apps/gosonos) to play Apple Music playlists on my Sonos system.

First up: how does the [Sonos Controller App (Your key to the ultimate listening experience)](https://www.sonos.com/en-us/controller-app) play Apple Music playlists?

Once I know that, I can update my own code and infrastructure to play my Apple Music playlists in response to Siri voice commands or Home App switches.

Using [Wireshark](https://www.wireshark.org) (or [tcpdump](https://www.tcpdump.org), etc, but I'm familiar with Wireshark) maybe I can sniff the traffic going to my Sonos speaker and see how the "play this playlist" command is sent. "Maybe", because if the traffic is SSL encrypted, I'll have to try something fancier like [mitmproxy](https://www.mitmproxy.org)[^2][^3].

[^2]: And if they're using [SSL pinning](https://owasp.org/www-community/controls/Certificate_and_Public_Key_Pinning), things could get tricky, [like  when my coffee machine vendor updated their auth flow AND added SSL pinning to their app](https://github.com/mikepartelow/homeslice/pull/83), causing a weeklong outage for tinkerers like myself.
[^3]: Spoilers: I happen to know from prior Sonos Wiresharking that they're not using SSL pinning, much less SSL. They're sending plaintext [SOAP](https://www.w3.org/TR/2000/NOTE-SOAP-20000508/), partying like it's 1999!

## Wiresharking It

First, I ungrouped my Sonos speakers to simplify my snooping landscape[^4]. Next, I picked one speaker to send commands to, and then obtained its IP address from the Sonos controller app.

That's all I needed to get started. I set up a filter in Wireshark[^5], making an educated guess[^6] that I was looking for HTTP traffic.

![wireshark filter](/assets/img/wireshark0.png). 

Then I used the Sonos Controller app to send the playlist to my speaker. Success! Wireshark caught a bunch of HTTP calls. 

![wireshark filter](/assets/img/wireshark1.png). 


Each one has an [XML](https://en.wikipedia.org/wiki/XML) payload, and one of them is going to a different path than all the rest. That seems like a good place to start. I looked at the XML payload for the request POSTing to `/MediaServer/ContentDirectory/Control`.

```xml
    <s:Envelope
        xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
            <u:Browse
                xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
                <ObjectID>
                    Q:0
                    </ObjectID>
                <BrowseFlag>
                    BrowseDirectChildren
                    </BrowseFlag>
                <Filter>
                    dc:title,res,dc:creator,upnp:artist,upnp:album,upnp:albumArtURI
                    </Filter>
                <StartingIndex>
                    0
                    </StartingIndex>
                <RequestedCount>
                    100
                    </RequestedCount>
                <SortCriteria>
                    </SortCriteria>
                </u:Browse>
            </s:Body>
        </s:Envelope>
```

Oh, well... that clearly isn't enqueuing my playlist. So much for lucky guesses. Starting from the top with the first request to `/MediaRenderer/AVTransport/Control`, that request clears the existing queue, the second request loads my playlist, the third seeks to the beginning of the playlist, and the fourth initiates playback. More stuff happens after that, but that seems like enough to sink my teeth[^7] into right now.

Here's the XML payload for loading the playlist:

```xml
    <s:Envelope
        xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
            <u:AddURIToQueue
                xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
                <InstanceID>
                    0
                    </InstanceID>
                <EnqueuedURI>
                    x-rincon-cpcontainer:1006206clibraryplaylist%3ap.PkxVBLKhJ6D0DB?sid=204&amp;flags=8300&amp;sn=421
                    </EnqueuedURI>
                <EnqueuedURIMetaData>
                    […] &lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot; xmlns=&quot;urn:schemas-upnp-org:meta
                    </EnqueuedURIMetaData>
                <DesiredFirstTrackNumberEnqueued>
                    0
                    </DesiredFirstTrackNumberEnqueued>
                <EnqueueAsNext>
                    0
                    </EnqueueAsNext>
                </u:AddURIToQueue>
            </s:Body>
        </s:Envelope>
```

🕵️‍♀️ Notice anything weird about that? I'll get back to the weird thing in a minute!

Here's the XML payload for initiating playback. To keep things extremely simple, I'm gambling that the "seek to playlist beginning" command is not necessary for my investigation and that for now I only need "load playlist" and "start playback".

```xml
    <s:Envelope
        xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
            <u:Play
                xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
                <InstanceID>
                    0
                    </InstanceID>
                <Speed>
                    1
                    </Speed>
                </u:Play>
            </s:Body>
        </s:Envelope>
```

[^4]: Ensuring that when I send the "play playlist" command, it goes to only one speaker, making it easier to find the transmission I'm looking for.
[^5]: Not the real IP address, obviously.
[^6]: Since I've done this before with Sonos, it was a little more than an educated guess.
[^7]: Just when I thought it was safe to go back into the network...

## Musical Curls

Now that I've got the XML payloads, I should be able to use [curl](https://curl.se/docs/manpage.html) (or [Postman](https://www.postman.com/downloads/), or `wget`, etc) to play my Apple Music playlist on my Sonos.

Wireshark also showed a bunch of HTTP headers being sent with each `POST`, but I know from experience that I only need the `SOAPACTION` header.

```shell
% cat > ./enq.xml
[ paste the first XML payload]
^D
% curl -X post -d @./enq.xml http://192.168.1.337:1400/MediaRenderer/AVTransport/Control -v -H 'SOAPACTION: "urn:schemas-upnp-org:service:AVTransport:1#AddURIToQueue"'
```

🤔 Huh, that didn't work. In fact, it gave me an `HTTP 500`, Internal Server Error.

Taking a closer look at the XML, I noticed this suspicious sequence:

```xml
[…] &lt;DIDL-Lite xmlns:dc=&quot
```

What the heck is `[…]`? That's some junk Wireshark added because I used the wrong flavor of "copy to clipboard". Wireshark offers several ways to copy things to the clipboard. So I tried again, using `copy as utf-8 text` this time. Here's what I got:

```xml
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
    s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:AddURIToQueue xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
            <EnqueuedURI>
                x-rincon-cpcontainer:1006206clibraryplaylist%3ap.PkxVBLKhJ6D0DB?sid=204&amp;flags=8300&amp;sn=421</EnqueuedURI>
            <EnqueuedURIMetaData>
                &lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot;
                xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot;
                xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;
                xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item
                id=&quot;1006206clibraryplaylist%3ap.PkxVBLKhJ6D0DB&quot;
                parentID=&quot;10fe2066libraryfolder%3af.4&quot;
                restricted=&quot;true&quot;&gt;&lt;dc:title&gt;Lost Due To
                Incompetence&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.playlistContainer.#PlaylistView&lt;/upnp:class&gt;&lt;upnp:albumArtURI&gt;https://is1-ssl.mzstatic.com/image/thumb/gen/600x600AM.PDCXS01.jpg?c1=C2D0D1&amp;amp;c2=98CDA9&amp;amp;c3=1D5061&amp;amp;c4=202615&amp;amp;signature=d591d89aff1818162f2347d14e2362509c1e1b8d342c396b5bb476f0cd402c10&amp;amp;t=TG9zdCBEdWUgVG8gSW5jb21wZXRlbmNl&amp;amp;tc=000000&amp;amp;vkey=1&lt;/upnp:albumArtURI&gt;&lt;r:description&gt;Playlists&lt;/r:description&gt;&lt;desc
                id=&quot;cdudn&quot;
                nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;SA_RINCON52231_X_#Svc52231-133a6555-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</EnqueuedURIMetaData>
            <DesiredFirstTrackNumberEnqueued>0</DesiredFirstTrackNumberEnqueued>
            <EnqueueAsNext>0</EnqueueAsNext>
        </u:AddURIToQueue>
    </s:Body>
</s:Envelope>
```

And with that corrected XML, the `curl` command worked. I could see in the controller that my playlist was loaded on to my Sonos speaker.

I ran the "play playlist" command, and the music played! My guess was correct: I didn't need (under these circumstances) to seek to the beginning of the playlist.

```shell
% cat > ./play.xml
[ paste the initiate playback XML, which never had any weird characters ]
^D
% curl -X post -d @./play.xml http://192.168.1.337:1400/MediaRenderer/AVTransport/Control -v -H 'SOAPACTION: "urn:schemas-upnp-org:service:AVTransport:1#Play"'
```

## Can I play any playlist, not just this one?

There's an obvious identifier (ID) in the `AddURIToQueue` XML payload: `libraryplaylist%3ap.PkxVBLKhJ6D0DB`. It appears twice. `%3a` is a urlencoded `:`, so that's `libraryplaylist:p.PkxVBLKhJ6D0DB`. 

Ideally I'd template the XML so I can plug in any playlist ID, then add that functionality to my existing [go-sonos](https://github.com/mikepartelow/homeslice/tree/main/apps/gosonos) code. But where do I get playlist IDs?

If I `Share` the playlist from the Apple Music app, I end up with a completely different ID, embedded in a Share Link like `https://music.apple.com/us/playlist/lost-due-to-incompetence/pl.u-38oWX9ECvqDrDL`.

Dropping variants of `pl.u-38oWX9ECvqDrDL` into the XML payload yields a HTTP 500 error.

Someone else has already figured out [how to use Share Links](https://github.com/SoCo/SoCo/blob/dd300be3ab63f6291e880de606f93fd52905c391/soco/plugins/sharelink.py#L216). What if I try [their approach](https://github.com/SoCo/SoCo/pull/886)?

```shell
% uvx --with soco python
>>> from soco import SoCo
>>> my_zone = SoCo('192.168.1.337')
>>> from soco.plugins.sharelink import ShareLinkPlugin
>>> sharelink=ShareLinkPlugin(my_zone)
>>> sharelink.add_share_link_to_queue("https://music.apple.com/us/playlist/lost-due-to-incompetence/pl.u-38oWX9ECvqDrDL")
1
```

Sure enough, that worked. Wireshark shows a new kind of XML payload, different from the ones I captured from the Sonos Controller app:

```xml
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
    s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:AddURIToQueue xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
            <EnqueuedURI>x-rincon-cpcontainer:1006206cplaylist%3apl.u-38oWX9ECvqDrDL</EnqueuedURI>
            <EnqueuedURIMetaData>
                &lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot;
                xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot;
                xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;
                xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item
                id=&quot;1006206cplaylist%3apl.u-38oWX9ECvqDrDL&quot; parentID=&quot;-1&quot;
                restricted=&quot;true&quot;&gt;&lt;dc:title&gt;&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.playlistContainer&lt;/upnp:class&gt;&lt;desc
                id=&quot;cdudn&quot;
                nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;SA_RINCON52231_X_#Svc52231-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</EnqueuedURIMetaData>
            <DesiredFirstTrackNumberEnqueued>0</DesiredFirstTrackNumberEnqueued>
            <EnqueueAsNext>0</EnqueueAsNext>
        </u:AddURIToQueue>
    </s:Body>
</s:Envelope>
```

This payload contains the share link ID `pl.u-38oWX9ECvqDrDL`.

What if I replace that with a different playlist share link ID, like the one in this share link: https://music.apple.com/us/playlist/the-bright-side/pl.u-DdANrvPujgVDVq ?

It worked! So now I know the XML snippet I can use in my own code, with the ID portion templated, to enqueue Apple Music playlists to my Sonos system, using easily obtainable share links from the Apple Music app itself. Hooray!

## Why not just use someone else's Sonos library? For instance, the one you just used in the previous section?

I like to [write software for myself]({% post_url 2024-04-07-write-software-for-yourself %}). It's fun. 

Plus, I got to practice my Wiresharking, and I learned a bit more about how Sonos works than if I'd just used someone else's library.

There's a limit, like when I started setting up an Android emulator to reverse engineer my coffee maker's new authentication flow. Software engineering is a discipline of tradeoffs, and at some point, the "fun" is no longer worth the time and effort traded off. Sometimes it's better to have some faith in your fellow tinkerers - *someone* is hacking away on the other side of the tradeoff.

This Sonos sniffing project doesn't come anywhere near that limit, it's pure fun!

## Why not use a SOAP library instead of sending random XML snippets?

Isn't that just what a SOAP library does?

Okay, not quite. But why do I need the extra complexity?

## Why not just RTFM?

Most of this is [very well documented](https://docs.sonos.com/docs/soap-requests-and-responses). 

See above re: "fun".

---
