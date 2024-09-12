---
layout: default
title: "Cool Golang callback idiom"
date: "2024/09/12"
---

I noticed something elegant and cool in some Go code I wrote recently at work.

Imagine we have a function that calls some external API to fetch a list of things. The function takes a callback that's called with each of the things returned by the external API.

```golang
// getThings doesn't check error codes, but you should. Be better than getThings.
func getThings(callback func(Thing) error) error {
    resp, _ := http.Get("https://things.website/api/things")

    var things []Thing
    _ = json.NewDecoder(resp.Body).Decode(&things)
    
    for _, thing := range things {
        _ = callback(thing)
    }
    
    return nil
}
```

How might we call this?

```golang
func printThings() {
    err := getThings(func(thing Thing) error {
        fmt.Println(thing)
        return nil
    })
}
```

What if we wanted to transform the and return a new list of things?

```golang
// transformThings fetches things from an exernal API, and Frobulates them before returning them to the caller
func transformThings() ([]Thing, error) {
    var things []Thing

    err := getThings(func(thing Thing) error {
        // Transform thing by Frobulating it
        things = append(things, Frobulate(thing))
        return nil
    })
    if err != nil {
        return nil, err
    }

    return things, nil
}
```

This can be simplified into something beautiful!

```golang
// transformThings fetches things from an exernal API, and Frobulates them before returning them to the caller
func transformThings() ([]Thing, error) {
    var things []Thing
    return things, getThings(func(thing Thing) error {
        // Transform thing by Frobulating it
        things = append(things, Frobulate(thing))
        return nil
    })
}
```

Look at that! It's gorgeous! 

It may look like we're returning an empty list of `Thing`s, but we definitely are not. `getThings()` must execute to completion before we return from `transformThings()`, and in so doing, `things` is populated before `transformThings()` returns.

The error code from `getThings()` is returned as the second return value of `transformThings()`, only this way requires 4 fewer lines of code.

Neat, huh?
