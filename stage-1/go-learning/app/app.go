// ######### stage 1
// package main

// import "fmt"

// func main() {
// 	fmt.Println("Hello, world.")
// }


//############# stage 2

package main

import 
(
	"fmt"
	"strconv"
)

var i = 32 // Global variable, will be overwritten by local variable inside function


func main() {

	// var i int // Once you declare a variable, you have to use it
	// i = 12 

	var i = 12 // Go can calculate the variable type itself 
	j := 15 // Another way to assign variable 
			// := only works in functions 
	x := j // variable can be assigned to another variable

	// var z float32 = j // Will not work as j is int. You will need to typecast it 
	
	var z float32 = float32(j) // Typecasting of variable types
	 
	//var foo string = string(i) // Will give a ascii value. You will need a strconv if you want to get actual string value
	var foo string = strconv.Itoa(i) 
	
	var bar bool = true 

	fmt.Println(i)
	fmt.Println(j)
	fmt.Println(x)
	fmt.Println(z)
	fmt.Printf("%v, %T\n",i ,i) // other way to print the variable value and type (v & t)
	fmt.Printf("%v, %T\n",foo, foo)
	fmt.Printf("%v, %T\n",bar, bar)
}	