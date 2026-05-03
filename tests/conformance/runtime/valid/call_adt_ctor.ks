type Shape = Circle(Int) | Rect(Int, Int)

fun area(s: Shape): Int =
  match (s) {
    Circle(r) => r * r
    Rect(w, h) => w * h
  }

println(area(Circle(4)))
// 16
println(area(Rect(3, 5)))
// 15
