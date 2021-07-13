/*######### stage 1
package main

import "fmt"

func main() {
	fmt.Println("Hello, world.")
}
*/

/*
############# stage 2 -- integers

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
*/

/*
########### stage 3 -- arithmetic operations and constants

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

	// binary operations
	fmt.Println(i & j)
	fmt.Println(i | j)
	fmt.Println(i ^ j)
	fmt.Println(i &^ j)

	// float 
	// there are two float32, float64. 
	// If you dont explitily mention, go will always choose the higher verision

	// x := 3.14
	// y := 5.6

	// Constants
	// compiler will not throw an error if constant is not used
	const USER_NAME = "darshan"
	fmt.Println(USER_NAME)

	// multiple constants can be grouped
	const (
		USER_MAIL = "darshan"
		USER_AGE= 12
	)

	// constants can be used with variables
	
	fmt.Println(i + USER_AGE )

 }	

 */


 /*
############# stage 4 -- arrays

package main

import 
(
	"fmt"

)

func main() {

	// array definitions
	var amounts [3]int = [3]int{10,20,30}
	amt := [3]int{10,20,30}
	flex_amt := [...]int{10,20,30,40} // [...] means no restrictions on arrays // so no out of bounds
	fmt.Printf("Amount: %v\n", amounts)
	fmt.Printf("Amount: %v\n", amt)
	fmt.Printf("length: %v\n", len(amt)) // length of array
	fmt.Printf("length: %v\n", len(flex_amt)) 


	//manipulate array
	amt[0] = 51
	fmt.Printf("updated Amount: %v\n", amt)

	a := amounts // a is a replica of amounts array and can be updated seperately from here on
	//a := &amounts // a is pointing to amounts. any change in a will change amounts array too
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


	//multidimensional array
	// array inside array

	var identityMatrix [3][3]int = [3][3]int{
			[3]int{1,0,0},
			[3]int{0,1,0},
			[3]int{0,0,1},
	}

	fmt.Println(identityMatrix)
	
	//arrays once created, you cannot add any new values to it
	// count of items in array will stay the same

}
*/


/*
############# stage 5 -- slices

similar to arrays but you can update the size
package main

import 
(
	"fmt"

)

func main() {

	//slices internally uses array
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
*/

//############# stage 6 -- maps

/*
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
*/

//############# stage 7 -- structs

/*
package main

import 
(
	"fmt"

)

// define struct
type Student struct {
	name string
	rollno int
	subjects []string


}

func main() {

	//create object of struct

	student1 := Student{
		name: "Darshan",
		rollno: 5,
		subjects: []string{
			"maths",
			"ophys",
			"chemistry"	,

		},
	}
	
	//This way will also work but not recommended as you will HAVE to match with how the Srtuct has been defined
	
	// student1 := Student{
	// 	"Darshan",
	// 	 5,
	// 	[]string{
	// 		"maths",
	// 		"ophys",
	// 		"chemistry"	,

	// 	},
	// }


	fmt.Println(student1)

	// getting specific values from struct
	fmt.Println(student1.name)
	fmt.Println(student1.subjects)

	// updating struct
	student1.name = "raul"
	fmt.Println(student1)


	student2 := student1

	student2.name = "darsh"
	fmt.Println(student1)
	fmt.Println(student2) 

	//embedding
	// no `is a` relationship, `has a` relationship
	// Composition is there but no Inheritance






}



*/


//############# stage 7 -- if and switch statements


package main

import 
(
	"fmt"

)

func main() {

	if true {

		fmt.Println("this is true")
	}


	if i := 2 ; i == 2 {

		fmt.Println("this statment will be printed")
	}
	if i := 2 ; i == 3 {

		fmt.Println("this statment will not be printed")
	}


	// if else
	// Note:  } else { is needed, else ide throws syntax issue
	if i := 2 ; i == 3 {
		fmt.Println("this statment will not be printed")
	} else {
		fmt.Println("this statment will be printed")

	}


	// if elseif else
	if i := 2 ; i == 3 {

		fmt.Println("this statment will not be printed")

	} else if  i==2 {

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