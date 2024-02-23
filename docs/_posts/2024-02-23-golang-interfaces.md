---
layout: default
title: "Write Small Interfaces"
date: "2024/02/23"
---

## Write Small Interfaces

### Top Down

The classic way of teaching interfaces, whether in [Go](https://gobyexample.com/interfaces) or [other languages](https://www.w3schools.com/java/java_interface.asp), usually starts with an abstract set of methods and then writing classes that implement those methods.

```go
type Flyer interface {
  TakeOff()
  Glide()
  Land()
}

type UnladenAfricanSwallow struct {} // implements TakeOff(), Glide(), and Land()
type LockheedSR71Blackbird struct {} // implements TakeOff(), Glide(), and Land()
```

This top-down approach often leads to interfaces with lots of methods, and abstractions that don't make any sense. 

Let's implement some Air Traffic Control.

```go
type Flyer interface {
  TakeOff()
  Glide()
  Land()
  GoAround()
}

func AirTrafficControl(f Flyer) {
  f.GoAround()
}
```

Now you have to implement `GoAround()` on `UnladenAfricanSwallow`, which makes no sense.

What if your V/STOL ground-attack aircraft needs some Air Traffic Control?

```go
type HawkerSiddeleyHarrier  struct {} // implements TakeOff(), Glide(), Land(), and GoAround()
```

Oh no! The Hawker Siddley Harrier can't glide. This interface makes no sense.

### Bottom Up

Things often turn out better if we start with a bottom-up approach and define interfaces in terms of what interface consumers require.

In this case, `AirTrafficController` requires a `GoAround()` method - and that's it. Anything that can perform a `GoAround()` will do, we don't care if it can `Glide()` (or even if it can [Land()](https://www.cntraveller.com/article/flying-hotel)).

```go
type GoArounder interface {
  GoAround()
}

func AirTrafficController(ga GoArounder) {
  ga.GoAround()
}

type UnladenAfricanSwallow struct {} // implements TakeOff(), Glide(), and Land()
type LockheedSR71Blackbird struct {} // implements TakeOff, Glide(), Land(), and GoAround()
type HawkerSiddeleyHarrier struct {} // implements TakeOff, Land(), and GoAround()
```

Now we don't have to add methods that don't make sense on `UnladenAfricanSwallow` and `HawkerSiddeleyHarrier`, and the type checker will prevent us from doing nonsensical stuff like passing an `UnladenAfricanSwallow` to `AirTrafficController`.

`AirTrafficController` doesn't need the full `Flyer` interface, it only calls `GoAround()`. Maybe nobody needs the full `Flyer` interface!

### Testing

Small interfaces make testing easier. 

```go
type mockGoArounder() struct {
  calls int
}

func (mga *mockGoArounder) GoAround() {
  mga.calls += 1
}

func TestATC(t *testing.T) {
  mga := mockGoArounder{}
  AirTrafficControl(mga)
  assert.Equal(t, 1, mga.calls)
}
```

We don't have to implement `TakeOff` etc. on `mockGoArounder`. The test file is smaller and easier to read. 

If we're using [TDD](https://quii.gitbook.io/learn-go-with-tests/) we can write our test and implement only what's needed for it to pass - we focus on what we're testing/implementing right now (`AirTrafficController`), not what we might need someday (`Land()`, `Glide()`, etc).

### The mindset

When you're writing your code, if you think "I sure wish I could call obj.Foo() right here to get the behavior I need", that's when you define the new `Fooer` interface! 

Write tests that pass a `stubFoo` or a `mockFoo` into your code, then when the tests pass, write the real thing that implements `Fooer`. This mindset even gives you the name of the interface, for free! It's whatever method you wished you could call, plus an `er` suffix.

This will also help you think about what really needs to be implemented in your concrete `Fooer` implementation. Do you really need those other methods you were imagining? 

## Summary

👉 Use Interfaces to describe what a function requires of its arguments  
👉 Don't use Interfaces to describe what a group of classes have in common  
👉 Minimize the number of methods on your Interface  
👉 this is not specific to Go
