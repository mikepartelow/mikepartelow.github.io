---
layout: default
title: "Go Isn't Ruby (thankfully)"
date: "2024/07/24"
---

## Background

> Code for this post is [here](https://github.com/mikepartelow/doit)

I often have to execute a sequence of steps to accomplish a task. Actually, now that I think about it, that's literally every time I accomplish a task. But anyways, if the task involves computers, I'd like to automate executing those steps.

There are many task pipeline orchestrators, but this one is (one of) mine. Here's what I learned writing it!

## Deeper Background

When executing a task pipeline, there are a few important considerations.

- Interruptions. The pipeline could crash or fail in between steps. It should be possible to `Resume` a failed pipeline, picking up where we left off without repeating expensive work.
- Genericity. If we're automating one pipeline task, odds are we'll automate another. The API shouldn't be specific to a particular set of inputs/outputs.
- Simplicity. Sure, we *could* use a Kubernetes-based task orchestrator to sync files between two directories on our laptop, but do we really want to? It shouldn't be half-baked, but it shouldn't be overbaked. It should omit features that aren't needed for the initial automation.
- Modernity. It has to be YAML-based if it's to be taken seriously.
- Fun. Software should be fun to write, and preferably fun to use.

I want to feed my pipeline orchestrator a YAML like this:

```yaml
name: Hello World
kind: recipe/v1
steps:
- kind: step/v1
  name: HelloFunc
- kind: step/v1
  name: WorldFunc
```

And have it execute `HelloFunc` followed by executing `WorldFunc`. If `HelloFunc` fails, then `WorldFunc` should not execute. If `HelloFunc` passed but `WorldFunc` fails, the next time I run the pipeline, `WorldFunc` should run, but not `HelloFunc`. 

This means I have to collect and store the pipeline state somehow. I could use a database, but I could also keep things extremely simple and try a text file. If that proves unworkable, I could escalate to higher complexity (a database).

## Go Isn't Ruby

The very first and nearly terminal roadblock I faced: in Go, there is simply no way at runtime to lookup a function by name. My YAML lists Go function names to execute, but there is no `Lookup(name string) SomeFunction` that I can use to get a function, given those function names.

Go's [reflect](https://pkg.go.dev/reflect) package provides similar functionality for struct members, but not for functions scoped outside of structs.

Go's linker omits functions that aren't called. Imagine this Go code:

```golang

func Foo() string { return "foo" }
func main() {
    p := LookupFuncByName("Foo")
    fmt.Println(p())
}
```

In that example, we use the fictional `LookupFuncByName` to get a reference to `Foo`, then execute the reference. This is possible in dynamic languages like [Ruby](https://ruby-doc.org/3.2.2/Object.html#method-i-public_send) and [Python](https://www.geeksforgeeks.org/call-a-function-by-a-string-name-python/).

In the example above, the Go linker will omit `Foo` from the final binary, because it's not explicitly called. Then the Lookup (if such a thing existed) would fail.

The Go designers chose prioritizing smaller binary size over dynamic function lookup. Whether we think that was a good tradeoff or not, there isn't and cannot be a `LookupFuncByName` in Go.

## The fix

The solution is as simple as it is boring. We just construct a `map[string]StepFunc` that maps names (strings) to Go functions. Then we use that map instead of reflection.

```golang

func Hello(input io.Reader) (io.Reader, error) {...}
func World(input io.Reader) (io.Reader, error) {...}

func main() {
    stepFuncMap := map[string]recipe.StepFunc{
        "HelloFunc": Hello,
        "WorldFunc": World,
    }

    r, err := recipe.New(strings.NewReader(helloWorldYaml), stepFuncMap)
}
```

## tl;dr

[Given this "recipe" YAML](https://github.com/mikepartelow/doit/blob/main/cmd/third_times_the_charm/third_times_the_charm.yaml):

```yaml
name: Third Time's The Charm
kind: recipe/v1
steps:
- kind: step/v1
  name: MkdirAndSucceedIfItDidNotAlreadyExist
- kind: step/v1
  name: CreateFileInDirAndSucceedTheThirdTime
- kind: step/v1
  name: Tada
```

[And this code](https://github.com/mikepartelow/doit/blob/main/cmd/third_times_the_charm/main.go):

```golang
// MkdirAndSucceedIfItDidNotAlreadyExist makes a directory if it doesn't already exist, and returns error if it did already exist.
// The directory name is read from input.
func MkdirAndSucceedIfItDidNotAlreadyExist(input io.Reader) (io.Reader, error) {...}

// CreateFileInDirAndSucceedTheThirdTime creates a temp file in the directory named in input.
// If the number of files in the directory is less than 3, it returns an error, otherwise, it returns a CSV list of directory name and the three files.
func CreateFileInDirAndSucceedTheThirdTime(input io.Reader) (io.Reader, error) {...}

// Tada reads 4 CSV values from input and writes a custom message to its output.
func Tada(input io.Reader) (io.Reader, error) {...}

//go:embed third_times_the_charm.yaml
var thirdTimesTheCharmYaml string

func main() {
	if len(os.Args) != 2 {
		fmt.Println("Usage:", os.Args[0], "directory")
		os.Exit(1)
	}

	directory := os.Args[1]
	stateFilename := directory + ".doit-state"

	// map names found in the recipe YAML to functions in this file
	stepFuncMap := map[string]recipe.StepFunc{
		"MkdirAndSucceedIfItDidNotAlreadyExist": MkdirAndSucceedIfItDidNotAlreadyExist,
		"CreateFileInDirAndSucceedTheThirdTime": CreateFileInDirAndSucceedTheThirdTime,
		"Tada":                                  Tada,
	}

	// if state exists for this program, read it and pass it to recipe.New()
	var opts []recipe.Option
	_, err := os.Stat(stateFilename)
	if err == nil {
		state := mustReadState(stateFilename)
		opts = append(opts, recipe.WithState(state))
	}

	// construct a new Recipe
	r, err := recipe.New(strings.NewReader(thirdTimesTheCharmYaml), stepFuncMap, opts...)
	check(err)

	// pass the directory as input to the Recipe pipeline
	output, err := r.Cook(strings.NewReader(directory))
	if err != nil {
		fmt.Println("ERROR: ", err.Error())

		// if there was an error, save the state
		state := r.State()
		mustWriteState(state, stateFilename)
		os.Exit(1)
	}

	_, err = io.Copy(os.Stdout, output)
	check(err)

	fmt.Println("")
}
```

Here's the output:

```bash
% ./third_times_the_charm spam
+ MkdirAndSucceedIfItDidNotAlreadyExist
+ CreateFileInDirAndSucceedTheThirdTime
ERROR:  Not succeeding until we've written 3 files. Currently 1.

% ./third_times_the_charm spam
outputIdx= 0
+ CreateFileInDirAndSucceedTheThirdTime
ERROR:  Not succeeding until we've written 3 files. Currently 2.

% ./third_times_the_charm spam
+ CreateFileInDirAndSucceedTheThirdTime
+ Tada
Tada! Wrote ["spam2664394372","spam3617723729","spam79845283"] to "spam"
```

See the implementation [here](https://github.com/mikepartelow/doit/blob/main/pkg/recipe/recipe.go).

## Takeaways

Despite Go's powerful reflection abilities, I was surprised to find no way in Go to look up a function by name at runtime. The reason turns out to make plenty of sense, but going into this project I had supposed that the `reflect` package would have that capability.

Although this implementation is quite rough, it is very simple, and even in its rough/simple state, it's powerful enough to be useful and generic enough to be useful for a range of tasks.

Before using this for anything real, I would add a lot more tests, implement per-step retries and timeouts, and add some lightweight observability.

As-is, this was a lot of fun to write, which was my chief design goal. ✅
