val width = 180
val height = 120
val maxIter = 80

val minRe = 0.0 - 2.0
val maxRe = 1.0
val minIm = 0.0 - 1.2
val maxIm = 1.2

val stepRe = (maxRe - minRe) / 180.0
val stepIm = (maxIm - minIm) / 120.0

fun runMandelbrotDense(): Int = {
  var y = 0
  var checksum = 0
  var yRe = minIm
  while (y < height) {
    var x = 0
    var xRe = minRe
    while (x < width) {
      val cRe = xRe
      val cIm = yRe

      var zr = 0.0
      var zi = 0.0
      var i = 0
      while (i < maxIter) {
        if ((zr * zr + zi * zi) > 4.0) {
          i := maxIter
        } else {
          val nextRe = zr * zr - zi * zi + cRe
          val nextIm = 2.0 * zr * zi + cIm
          zr := nextRe
          zi := nextIm
          i := i + 1
        }
        ()
      }

      checksum := checksum + i
      x := x + 1
      xRe := xRe + stepRe
      ()
    }
    y := y + 1
    yRe := yRe + stepIm
    ()
  }

  checksum
}

println(runMandelbrotDense())
