# Go Cheatsheet
## Topics covered

```
======== Essentials
- go mod init
- simple hello world program
- go mod tidy
- go build
- variables
- constants
- arithmatic operations
- printf formats
- if else
- switch case
- error handling
- maps
- slices
- arrays
- for loop and all its scenarios
- functions
- defer
- multiple packages in a module
- exporting functions from diff package

========== Should know
- pointers
- Structs
- Methods
- time module usecases
- json
- AWS sdk
- AWS lambda
- http api
- making http call
- creating a cli

========== Advanced
- gorm
- Goroutines
- Channels
- Interfaces
- Context
- Generics
```

## Creating a go module

note: prefer to keep a remote module name, helps in other modules importing it

```
cd <project-folder>
go mod init github.com/<repo path> or bitbucket.org/<repo path> or any-thing-else 
```

## Hello world

```
vim main.go
>>>>>>
package main

import "fmt"

func main() {
    // This is a comment
	fmt.Println("Hello, world.")
}
<<<<<<<
go run main.go
```

## Variables


```
vim main.go
>>>>>>
package main

import 
(
	"fmt"
	"strconv"
)

var i = 32 // Global variable, will be overwritten by local variable inside function


func main() {

	// Once you declare a variable, you have to use it

    var d int = 5 // most common way of declaring variable
	var i = 12 // Go can calculate the variable type itself 
	j := 15 // := only works in functions 
	x := j // variable can be assigned to another variable

	// var z float32 = j // Will not work as j is int. You will need to typecast it 
	
	var z float32 = float32(j) // Typecasting of variable types
	 

	var bar bool = true 

    fmt.Println(d)
	fmt.Println(i)
	fmt.Println(j)
	fmt.Println(x)
	fmt.Println(z)
	
}
<<<<<<<

go run main.go
```


## Constants

```
vim main.go
>>>>>>
package main



import 
(
	"fmt"

)

const pi = 3.14159
const secondsPerMinute = 60
const metersPerKilometer = 1000

func main(){

    fmt.Println(pi)
}



<<<<<<
go run main.go

```

## Arithmatic operations


```
vim main.go
>>>>>>
package main

import 
(
	"fmt"

)

func main() {

	i := 20
	j := 5
	// arithmetic operations
	fmt.Println(i+j)
	fmt.Println(i*j)
	fmt.Println(i/j)
	fmt.Println(i-j)
	fmt.Println(i%j)

 }
<<<<<<
go run main.go

```

## Print Formatting


```
vim main.go
>>>>>>
package main

import 
(
	"fmt"

)

func main() {

	fmt.Printf("Hello, %s!\n", "World") 

    value := 42
    fmt.Printf("The value is: %d\n", value) 

    pi := 3.14159
    fmt.Printf("Pi is approximately: %.2f\n", pi)

    name := "Alice"
    age := 30
    fmt.Printf("%s is %d years old.\n", name, age) 

    fmt.Printf("type: %T\n", age)

    fmt.Printf("bool: %t\n", true)
 }
<<<<<<
go run main.go

```
## If else


```
vim main.go
>>>>>>
package main

import 
(
	"fmt"

)

func main() {

	if true {

		fmt.Println("this is true")
	}
    
    i := 2
    if i == 2 {

		fmt.Println("this statment will be printed")
	}

    // same syntax as above

	if i := 2 ; i == 2 {

		fmt.Println("this statment will be printed")
	}


	// if else
	// Note:  } else { is needed, else ide throws syntax issue

	if i := 2 ; i == 3 {
		fmt.Println("this statment will not be printed")
	} else {
		fmt.Println("this statment will be printed")
	}


	// if - elseif - else
	if i := 2 ; i == 3 {

		fmt.Println("this statment will not be printed")

	} else if i==2 {

		fmt.Println("this statment will be printed")

	} else {
		fmt.Println("this statment is default")

	}

	i := 10
	j := 20

	if i < j {

		fmt.Println(" i is less than j ")
	}
 }
<<<<<<
go run main.go

```

## Error Handling


```
vim main.go
>>>>>>
package main


import (
    "fmt"
    "os"
)

func openFile(filename string) error {
    file, err := os.Open(filename)
    if err != nil {
        return fmt.Println(err) 
    }
    defer file.Close()  

    // Process the file here
    return nil
}

func main() {
    err := openFile("nonexistent.txt")  
    if err != nil {
        fmt.Println("Error:", err)
    } 
}

<<<<<<
go run main.go

```


## Switch


```
vim main.go
>>>>>>
package main

import 
(
	"fmt"

)

func main() {

	switch i := 1+1; i {
		case 1:
			fmt.Println("This is 1")
		case 2:
			fmt.Println("This is 2") // this will be printed
		case 3:
			fmt.Println("This is 3")
		default:
			fmt.Println("This is default") // in case nothing matches
	}

 }
<<<<<<
go run main.go

```

## Array


```
vim main.go
>>>>>>
package main

import 
(
	"fmt"

)

func main() {

	// array definitions
	var amounts [3]int = [3]int{10,20,30}
	amt := [3]int{10,20,30} // short hand
    
    //arrays once created, you cannot add any new values to it
	// count of items in array will stay the same


	fmt.Printf("Amount: %v\n", amounts)
	fmt.Printf("Amount: %v\n", amt)
	fmt.Printf("length: %v\n", len(amt)) // length of array

	//manipulate array
	amt[0] = 51
	fmt.Printf("updated Amount: %v\n", amt)

    // copy array
	a := amounts // a is a replica of amounts array and can be updated seperately from here on

	fmt.Printf("Amount: %v\n", a)


	//slicing array

	b := [...]int{1,2,3,4,5,6,7,8,9,10}
	c := b[:] // complete b array copied in c
	d := b[2:] // from 2nd to last element copied
	e := b[:5] // from 0th to 5th element copied
	f := b[2:7] // from 2nd to 7th element copied

	fmt.Printf("Amount: %v\n", b)
	fmt.Printf("Amount: %v\n", c)
	fmt.Printf("Amount: %v\n", d)
	fmt.Printf("Amount: %v\n", e)
	fmt.Printf("Amount: %v\n", f)

	


 }
<<<<<<
go run main.go

```

## Slice


```
vim main.go
>>>>>>
package main

import 
(
	"fmt"

)

func main() {

	// slices internally uses array
	// creates a new array internally when you update the size

	var slice1 []int = []int{1,2,3}
 	fmt.Println(slice1)

	var slice2 []int = slice1 // slice copy will be a pointer. eg if you update slice 1 , slice2  will also be updated

	slice2[0]=4

	fmt.Println(slice1)
	fmt.Println(slice2)

	// other way of creating slice
	var slice3 []int = make ([]int, 3, 10) // 3 is the size, 10 is the capacity
	fmt.Println(slice3)

	//appending to slice
	var slice4 []int = append(slice1 ,5)
	fmt.Println(slice4)


 }
<<<<<<
go run main.go

```

## Map


```
vim main.go
>>>>>>
package main

import 
(
	"fmt"

)

func main() {

	shoppingCart := map[string]int{

			"Keyboard": 100,
			"Mouse": 100,
			"Laptop": 100,
	}

	fmt.Println(shoppingCart)

	// other way to create map

	/*
	shoppingCart = make(map[string]int)
	shoppingCart = map[string]int{

		"Keyboard": 100,
		"Mouse": 100,
		"Laptop": 100,
	}
	



}
<<<<<<
go run main.go

```


## For looping

```
	**1. Classic Three-Component For Loop**

	```go
	// Sum numbers from 1 to 10
	sum := 0
	for i := 1; i <= 10; i++ {
		sum += i
	}
	fmt.Println("Sum:", sum) 
	```

	* **Initialization:** `i := 1` initializes the loop variable.
	* **Condition:** `i <= 10`  is evaluated before each iteration.
	* **Post-Iteration:**  `i++` increments the loop variable after each iteration.

	**2. While-Loop Behavior**

	```go
	// Print powers of 2 less than 100
	n := 1
	for n < 100 {
	fmt.Println(n)
	n *= 2
	}
	```

	* Omits the initialization and post-iteration parts; behaves like a while loop.  

	**3. Infinite Loop**

	```go
	for {
		// Do something repeatedly until a 'break' statement is encountered
		// similar to do while true in python
	}
	```

	* Omits all components for an infinite loop; use with caution and include a way to terminate (`break`).

	**4. Range over Arrays, Slices, Maps, Strings**

	```go
	numbers := []int{2, 4, 6, 8}
	for i, num := range numbers {
		fmt.Println("Index:", i, "Value:", num)
	}

	for key, value := range map[string]int{"one": 1, "two": 2} {
		fmt.Println(key, ":", value)
	}

	for _, char := range "Hello, World!" {
		fmt.Printf("%c\n", char) 
		// _ above means, we donot need the index and hence skipping it
	}
	```

	* **range** iterates over elements and provides key/value (maps) or index/value (arrays, slices, strings).

	**5. Skipping Iterations with `continue`**

	```go
	for i := 0; i < 10; i++ {
		if i % 2 == 0 {
			continue // Skip even numbers
		}
		fmt.Println(i)
	}
	```

	**6. Breaking Out of the Loop with `break`**

	```go
	for i := 0; i < 10; i++ {
		if i == 5 {
		break // Exit the loop
		}
		fmt.Println(i)
	}
	```

	**Important Notes**

	* **The Blank Identifier (`_`)**: Use `_` to ignore an index or value returned by `range`. For example:

	```go
	for _, value := range someArray { 
			// Only care about the value
	} 
	```

	* **Scope:** Loop variables declared in the initialization statement are only visible within the loop.

```


## Functions


```
vim main.go
>>>>>>
package main

import 
(
	"fmt"

)

func greet(name string) {
    fmt.Println("Hello,", name)
}

func calculateArea(length, width float64) float64 {
    return length * width
}

func calculateSumAndAverage(x, y int) (int, float64) {
    sum := x + y
    average := float64(sum) / 2
    return sum, average
}

func printValues(prefix string, values ...int) {
    fmt.Println(prefix)
    for _, value := range values {
        fmt.Println(value)
    }
}

func main() {
    greet("Golang Enthusiast")
	
	area := calculateArea(5, 3)
    fmt.Println("Area of rectangle:", area)

    sum, average := calculateSumAndAverage(10, 20)
    fmt.Println("Sum:", sum)
    fmt.Println("Average:", average)

	// variadic functions, any number of arguments
	printValues("Numbers:", 1, 2, 3)
    printValues("More Numbers:", 4, 5, 6, 7)
}


<<<<<<
go run main.go

```

## Defer


```
vim main.go
>>>>>>
package main

import 
(
	"fmt"

)

func demo() {
    fmt.Println("Starting...")

	// used when you want to ensure a command gets
	// executed but at the end very end of the
	// function 
    defer fmt.Println("Middle")  // Executed second
    defer fmt.Println("First")  // Executed last

    fmt.Println("Ending...")
}

func main() {
    demo()
} 


<<<<<<
go run main.go


Output:

Starting...
Ending...
Middle
First

```

