# Muki

Muki is a ruby-esque language written in lua that transpiles to Lua. The core goals for this were:

1. Reduce code/word repition.
2. Add useful features I wish Lua had

I like to think that it covers these well. To reduce word repition muki has shortcuts for `self:` and `self.` in the form of `\` and `@`. For example, instead of needing to write `self.thing` everywhere in a class you can just write `@thing`.
Another example of reducing code/word repetition is thanks to `case/when`. Here's what it might look like in Lua:
```lua
if ext == "wav" or ext == "mp3" or ext == "ogg" or ext == "flac" then
    -- handle audio
end
```
And now in muki
```rb
case ext
when "wav|mp3|ogg|flac"
    # handle audio
end
```
My "unbiased" opinion is that this is a lot more readable and cleaner. This is just a couple of examples of reducing word repetition. Muki does have a lot more that I won't bother covering in this introduction.


## Installation
```bash
curl -fsSL https://github.com/protbox/Luby/raw/refs/heads/main/install.sh | sudo sh
```

## Usage
```bash
muki source.rb > output.lua
```

## Uninstall
I'd prefer you didn't, but if you really have to:

```bash
sudo rm /usr/local/bin/muki
```

## What does it change?

It's important to understand that Muki is not Ruby, even though at first glance it may look like it! You can't throw down a full snippet of Ruby and expect it to work - it probably won't.
Muki uses a Ruby-like syntax and converts it to Lua. So, let's go over how Muki differs from Lua.

### Assigning local variables

Put simply, `let` replaces `local`. So, instead of typing:

```lua
local x, y = 5, 0
```

You'd write

```rb
let x, y = 5, 0
```

### Arrays/Hashes (tables)
To assign a key/value table (hash or associative array, whatever you want to call them), the structure is:

```rb
let t = {
    :key => value
}
```

Regular arrays haven't changed
```rb
let fruits = {'apple', 'orange', 'banana'}
```

### Loops
Now that we've covered arrays, it might be a good time to learn how loops are created. We no longer use `for` and `i/pairs`.

For indexed arrays we use `.each`. Very similar to Ruby. This is equivalent to using `ipairs` in Lua.

```rb
let fruits = {'apple', 'orange', 'banana'}

fruits.each do |fruit|
    print("#{fruit}")
end
```
Unlike Lua, you can ommit the index assignment. If you still want it, you can get it, though.

```rb
fruits.each do |i, fruit|
    print("#{i}: #{fruit}")
end
```

If you prefer, muki also supports ruby's braced `each`.

```rb
1..10.each {|i| print(i)}
```

For hashes, use `.each_pair` instead. This is equivalent to using `pairs` in Lua.

```rb
let person = {:name => "Mrs. Froot", :house_no => 5}

person.each_pair do |key, value|
    print("#{key}: #{value}")
end
```

### Unary Operators
Another thing I wish Lua had was unary/compound operators. It's a small thing, but it looks cleaner and saves time.
As an example, in Lua you might increment a variable like so:

```lua
local x = 9
x = x + 1 -- x is now 10
```

But in Muki, we can use `+=, -= and *=` which does the same thing, but without having to write out the variable twice.

```rb
let x = 9
x += 1 # x is now 10
```
Beautiful, right?

### String Interpolation
One of things I disliked about lua the most was having to concatenate strings and variables with `..`. I really liked the way ruby handles it with `#{var}`, so we have that.

```rb
let cat = "Whiskers"
print("The cats name is #{cat}")
```
All this is doing is replacing `#{var}` with `" .. var .. "`

### Functions

Functions in Muki use the `def` keyword. The rest of it is pretty much the same as Lua, but there are a few special cases.

```rb
def foo(arg1, arg2)
end
```

Special case 1 is you don't need to use parenthesis if you don't need any arguments.

```rb
def foo
end
```

Special case 2. If you want to create a local function, append `: Local` to the end of it.

```rb
def foo : Local # -> local function foo()
end
```

### Classes

Muki will inject a very small class implementation when it detects a `class` inside a file.
Here's a simple class in Muki:

```rb
class People
    def initialize # gets called when you create a new instance
        print("Person created.")
    end
end
```
Creating an instance is fairly similar to Lua, but we use `let` instead of `local` for assining local variables. To call the instance we can use `ClassName()` or a more ruby-like approach with `ClassName.new`

```rb
let person = People.new # prints Person created.
```

#### Inheritance

You can inherit from **one** parent. This gives your class all of the traits of the parent class, but allows you to override them at will. Very powerful stuff, and can save you a lot of code duplication.
To inherit, we use `class_name < parent_class`.
Let's continue with our `People` class, but add a `Person` class that inherits it.

```rb
class People
    def initialize(name)
        @name = name or "Unknown"
    end

    # pretty contrived example
    def get_full_name
        @name = "Mr. #{@name}" # self.name = "Mr. " .. self.name
    end
end

class Person < People
    def initialize(name)
        super
        print("#{@name} was created") # this was set in People:initialize thanks to super
    end

    def get_full_name
        super
        return @name
    end
end

let p = Person.new("Cactus Bill")
print("Person's name is: #{p:get_full_name()}")
```
I know what you're thinking - "Woah, back up. You did new stuff there", and you'd be right. We did two new things.
1. `super` is shorthand for `ClassName.super.MethodName(args)`. This just calls the parent method with the arguments supplied by the method.
2. We used `@`. This is just an alias for `self.`. That's all. You'll also find `\` is an alias for `self:`

As an additional note, you can retrieve the current classes name with the special variable `@__name`

### Case/When

Muki comes shipped with a basic version of Ruby's `case/when`, which is kind of like a switch block, or if we're talking Lua, you can think of it as `if/elseif/else`.
The basic structure is:
```rb
case topic
    when expr
        # logic
    when expr
        # logic
    else # optional no match found clause
        #logic
end
```
When converted to Lua, each when statement becomes `if/elseif topic expr then`.
There's a few auto patterns you can use with these too.

```rb
case topic
    when "snug%" # topic starts with "snug"
    when "%ling" # topic ends with "ling"
    when "snug|bug|rug" # topic matches any of the words between the pipes (or)
    when 5..10   # topic is a number and is within the range of 5 and 10
    when topic   # topic == topic
end
```
For anything else, just use standard lua expressions, but keep in mind that `topic` will be automatically placed at the front. If you need more flexibility, just use if/elseif. `case/when` is perfect for simple checks and when you need a lot of them on the same topic.

### Conditional statements
Most of these are exactly the same as Lua with two main exceptions.
1. `elseif` is now `elsif`
2. `then` is not required

```rb
if expr
    if expr
    elsif expr
        if expr
        end
    else
    end
else
end
```

The same goes with `while` and `for`, just drop the `do`, but everything else stays the same.

