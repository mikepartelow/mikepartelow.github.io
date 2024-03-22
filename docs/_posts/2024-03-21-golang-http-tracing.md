---
layout: default
title: "HTTP Request Tracing in Go"
date: "2024/03/21"
---

## What?

Go's standard library includes [net/http/trace](https://pkg.go.dev/net/http/httptrace), for registering callbacks that are invoked at certain points during the HTTP request lifecycle, and the [net/http.RoundTripper](https://pkg.go.dev/net/http#RoundTripper) `interface`, which can be used to interact with HTTP [Requests](https://pkg.go.dev/net/http#Request) and [Responses](https://pkg.go.dev/net/http#Response), even ones for Request/Response cycles initiated outside your own code.

## Why?

You can use these tools to debug when your HTTP client code is slow or misbehaving. You can also use it to gain insight into networking protocols and properties. But mostly: because it's cool.

## Example

You've noticed[^1] that loading `http://google.com` seems a bit slow. Why might that be?

Let's find out by writing some code.

```golang
package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

const url = "http://google.com/"

func main() {
	before := time.Now()

	resp := must(http.Get(url))
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		fmt.Println("Unexpected HTTP response: ", resp.StatusCode)
		os.Exit(1)
	}

	body := must(io.ReadAll(resp.Body))
	fmt.Println("len(body)=", len(body))
	fmt.Println("HTTP GET ", url, " took ", time.Since(before))
}

// must returns the `any` of a func that returns (any, error), or panics if the func returned an error
func must[T any](thing T, err error) T {
	if err != nil {
		panic(err)
	}
	return thing
}
```

This simply times the round trip time of an HTTP GET Request and Response.

```bash
% go run main.go
len(body)= 18437
HTTP GET  http://google.com/  took  194.279ms
```

Wow, that's incredibly slow! Nobody's got time to wait that long. Can we dig deeper? Let's add some [net/http/httptrace](https://pkg.go.dev/net/http/httptrace) code to see how long it takes for Google's reply to reach us. We can use the `GotFirstResponseByte` callback of a [httptrace.ClientTrace](https://pkg.go.dev/net/http/httptrace#ClientTrace) to find out.

```golang
package main

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptrace"
	"os"
	"time"
)

const url = "http://google.com/"

func main() {
	req := must(http.NewRequest(http.MethodGet, url, nil))

	before := time.Now()

	trace := &httptrace.ClientTrace{
		GotFirstResponseByte: func() {
			fmt.Println("got first response byte after", time.Since(before).String())
		},
	}

	req = req.WithContext(httptrace.WithClientTrace(req.Context(), trace))

	resp := must(http.DefaultClient.Do(req))
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		fmt.Println("Unexpected HTTP response: ", resp.StatusCode)
		os.Exit(1)
	}

	body := must(io.ReadAll(resp.Body))
	fmt.Println("len(body)=", len(body))
	fmt.Println("HTTP GET ", url, " took ", time.Since(before))
}

// must returns the `any` of a func that returns (any, error), or panics if the func returned an error
func must[T any](thing T, err error) T {
	if err != nil {
		panic(err)
	}
	return thing
}
```

And, run it.

```bash
% go run main.go
got first response byte after 41.494959ms
got first response byte after 120.874209ms
len(body)= 18447
HTTP GET  http://google.com/  took  122.415959ms
```

Hey, that's 37% faster! That's just normal WiFi/internet variation. What's more interesting is that we got two calls to `GotFirstResponseByte`. What's going on? Why did we get two responses to our one HTTP Get Request? Let's add a custom [net/http.RoundTripper](https://pkg.go.dev/net/http#RoundTripper) to help us dig deeper.

```golang
package main

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptrace"
	"os"
	"time"
)

const url = "http://google.com/"

// tripper wraps an existing http.RoundTripper and prints information about Requests and Responses.
type tripper struct {
	transport http.RoundTripper
}

// RoundTrip implements http.RoundTrip. It prints information about the Request and Response to stdout.
func (t *tripper) RoundTrip(req *http.Request) (*http.Response, error) {
	fmt.Println("->", req.Proto, req.Method, req.URL)
	resp, err := t.transport.RoundTrip(req)
	if err == nil {
		fmt.Println("<-", resp.Proto, resp.Status, resp.ContentLength)
	}
	return resp, err
}

func main() {
	req := must(http.NewRequest(http.MethodGet, url, nil))

	before := time.Now()

	trace := &httptrace.ClientTrace{
		GotFirstResponseByte: func() {
			fmt.Println("got first response byte after", time.Since(before).String())
		},
	}

	req = req.WithContext(httptrace.WithClientTrace(req.Context(), trace))

	// replace the client's default Transport with a tripper-wrapped default Transport
	client := http.Client{Transport: &tripper{http.DefaultTransport}}

	resp := must(client.Do(req))
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		fmt.Println("Unexpected HTTP response: ", resp.StatusCode)
		os.Exit(1)
	}

	body := must(io.ReadAll(resp.Body))
	fmt.Println(len(body))
	fmt.Println("len(body)=", len(body))
	fmt.Println("HTTP GET ", url, " took ", time.Since(before))
}

// must returns the `any` of a func that returns (any, error), or panics if the func returned an error
func must[T any](thing T, err error) T {
	if err != nil {
		panic(err)
	}
	return thing
}
```

Run it.

```bash
go run main.go
-> HTTP/1.1 GET http://google.com/
got first response byte after 38.837166ms
<- HTTP/1.1 301 Moved Permanently 219
->  GET http://www.google.com/
got first response byte after 124.932708ms
<- HTTP/1.1 200 OK -1
18436
len(body)= 18436
HTTP GET  http://google.com/  took  125.791458ms
```

Aha! Google issues an [HTTP 301 Redirect](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/301), and Go's [http.Client](https://pkg.go.dev/net/http#Client) follows Redirects by default. So we are actually making two HTTP requests, not one. That explains the two calls to our `GotFirstResponseByte` callback.

Now, with deeper understanding, we can optimize things a little.

What if we change the `http://google.com` in our code to `http://www.google.com`? Then Google shouldn't need to issue a Redirect, and we won't need to make a second RoundTrip.

Here's the output:

```bash
go run main.go
-> HTTP/1.1 GET http://www.google.com/
got first response byte after 71.123959ms
<- HTTP/1.1 200 OK -1
18406
len(body)= 18406
HTTP GET  http://www.google.com/  took  72.230834ms
```

Wow! A perfect 42% improvement. [Profound](https://en.wikipedia.org/wiki/42_(number)#:~:text=The%20number%2042%20is%2C%20in,period%20of%207.5%20million%20years.)!

## What was all that about?

There exist a variety of tools to help with analyses like this. But writing our own code gives us the opportunity to explore Go's amazing standard library, practice[^2] good coding habits and language-specific idioms, and run sophisticated exerpiments to gain deeper insights.

We could expand this code in a number of directions, including adding more callbacks to our trace, adding `for` loops to compute means and medians, lists of different urls to fetch, [concurrent](https://go.dev/tour/concurrency/11) requests, HTTP header injection, and so on. 

Also, it's fun!

---

[^1]: Somehow.
[^2]: Makes Perfect.
