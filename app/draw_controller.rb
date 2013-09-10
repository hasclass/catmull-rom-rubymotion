class DrawController < UIViewController
  LINE_WIDTH = 3.0

  attr_reader :imageView
  attr_accessor :previousPoint
  attr_accessor :drawnPoints
  attr_accessor :cleanImage

  def viewDidLoad
    super
    @imageView = UIImageView.alloc.initWithFrame(self.view.bounds)
    @imageView.backgroundColor = UIColor.whiteColor
    @imageView.image = UIImage.new

    @recog = UIPanGestureRecognizer.new
    @recog.delegate = self
    @imageView.addGestureRecognizer(@recog)
    self.view.addSubview @imageView
  end

  module TouchEventHandler
    # drawLineFromPoint:to_Point:image is a simple utility method that draws a line over a UIImage and returns the resulting UIImage.
    # Now UIResponder‘s touch handling methods will be overridden:
    def touchesBegan(touches, withEvent:event)
      # retrieve the touch point
      touch = touches.anyObject
      currentPoint = touch.locationInView(self.view)

      # Its record the touch points to use as input to our line smoothing algorithm
      self.drawnPoints = NSMutableArray.arrayWithObject(NSValue.valueWithCGPoint(currentPoint))

      self.previousPoint = currentPoint

      # we need to save the unmodified image to replace the jagged polylines with the smooth polylines
      self.cleanImage = imageView.image.retain
    end

    def touchesMoved(touches, withEvent:event)
      touch = touches.anyObject
      currentPoint = touch.locationInView(self.view)

      drawnPoints.addObject(NSValue.valueWithCGPoint(currentPoint))

      imageView.image = self.drawLineFromPoint(previousPoint, toPoint:currentPoint, image:self.imageView.image)
      self.previousPoint = currentPoint
    end

    def touchesEnded(touches, withEvent:event)
      generalizedPoints = self.douglasPeucker(drawnPoints, epsilon:2)
      splinePoints      = self.catmullRomSpline(generalizedPoints, segments:8)
      imageView.image   = self.drawPathWithPoints(splinePoints, image:cleanImage)
      # drawnPoints.release
      # cleanImage.release
    end

    def touchesCancelled(touches, withEvent:event)
      NSLog("touchesCancelled")
    end
  end

  include TouchEventHandler


  # UIImage
  def drawLineFromPoint(from_Point, toPoint:to_Point, image:image)
    screensize = self.view.frame.size

    UIGraphicsBeginImageContext(screensize)
    context = UIGraphicsGetCurrentContext()
    image.drawInRect(CGRectMake(0, 0, screensize.width, screensize.height))

    CGContextSetLineCap(context, KCGLineCapRound)
    CGContextSetLineWidth(context, LINE_WIDTH)
    CGContextSetRGBStrokeColor(context, 1, 0, 0, 1)
    CGContextBeginPath(context)
    CGContextMoveToPoint(context, from_Point.x, from_Point.y)
    CGContextAddLineToPoint(context, to_Point.x, to_Point.y)
    CGContextStrokePath(context)

    rect = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    rect
  end


  # Draws a path to an image and returns the resulting image */
  def drawPathWithPoints(points, image:image)
    screenSize = self.view.frame.size
    UIGraphicsBeginImageContext(screenSize)
    context = UIGraphicsGetCurrentContext()
    image.drawInRect(CGRectMake(0, 0, screenSize.width, screenSize.height))

    CGContextSetLineCap(context, KCGLineCapRound)
    CGContextSetLineWidth(context, LINE_WIDTH)
    CGContextSetRGBStrokeColor(context, 0, 0, 1, 1)
    CGContextBeginPath(context)

    count = points.count
    point = points[0].CGPointValue
    CGContextMoveToPoint(context, point.x, point.y)
    1.upto(count - 1) do |i|
      point = points.objectAtIndex(i).CGPointValue
      CGContextAddLineToPoint(context, point.x, point.y)
    end
    CGContextStrokePath(context)

    ret = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    ret
  end


  def douglasPeucker(points, epsilon:epsilon)
    count = points.count
    return points if (count < 3)

    # Find the point with the maximum distance
    dmax = 0;
    index = 0;
    1.upto(count -2) do |i|
      point = points[i].CGPointValue
      lineA = points[0].CGPointValue
      lineB = points[count - 1].CGPointValue
      d = self.perpendicularDistance(point, lineA:lineA, lineB:lineB)
      if d > dmax
        index = i;
        dmax = d;
      end
    end

    # //If max distance is greater than epsilon, recursively simplify
    resultList = nil
    if (dmax > epsilon)
      recResults1 = self.douglasPeucker(points.subarrayWithRange(NSMakeRange(0, index + 1)), epsilon: epsilon)
      recResults2 = self.douglasPeucker(points.subarrayWithRange(NSMakeRange(index, count - index)), epsilon: epsilon)
      tmpList = NSMutableArray.arrayWithArray(recResults1)
      tmpList.removeLastObject
      tmpList.addObjectsFromArray(recResults2)
      resultList = tmpList
    else
      resultList = [points[0], points[count - 1]]
    end

    resultList
  end

  def perpendicularDistance(point, lineA:lineA, lineB:lineB)
    v1 = CGPointMake(lineB.x - lineA.x, lineB.y - lineA.y);
    v2 = CGPointMake(point.x - lineA.x, point.y - lineA.y);
    lenV1 = Math.sqrt(v1.x * v1.x + v1.y * v1.y)
    lenV2 = Math.sqrt(v2.x * v2.x + v2.y * v2.y)
    angle = (v1.x * v2.x + v1.y * v2.y).to_f / (lenV1 * lenV2)
    # somehow the calculation here can be off by 0.000045. Rounding error?
    if angle < -1.0
      angle = -1.0
    elsif angle > 1.0
      angle = 1.0
    end
    angle = Math.acos(angle)
    Math.sin(angle) * lenV2;
  end

  def catmullRomSpline(points, segments:segments)
    count = points.count
    return points if (count < 4)

    b = Array.new(segments) do
      Array.new(4)
    end

    # precompute interpolation parameters
    t = 0.0
    dt = 1.0 / segments
    # for (i = 0; i < segments; i++, t+=dt) do
    0.upto(segments - 1) do |i|
      t += dt
      tt = t*t
      ttt = tt * t
      b[i][0] = 0.5 * (-ttt + 2.0*tt - t)
      b[i][1] = 0.5 * (3.0*ttt -5.0*tt +2.0)
      b[i][2] = 0.5 * (-3.0*ttt + 4.0*tt + t)
      b[i][3] = 0.5 * (ttt - tt)
    end

    resultArray = []
    i = 0 # first control point
    resultArray << points[0]

    # for ( j = 1; j < segments; j++) do
    1.upto(segments - 1) do |j|
      pointI   = points[i    ].CGPointValue
      pointIp1 = points[i + 1].CGPointValue
      pointIp2 = points[i + 2].CGPointValue
      px = (b[j][0]+b[j][1])*pointI.x + b[j][2]*pointIp1.x + b[j][3]*pointIp2.x;
      py = (b[j][0]+b[j][1])*pointI.y + b[j][2]*pointIp1.y + b[j][3]*pointIp2.y;
      resultArray << NSValue.valueWithCGPoint(CGPointMake(px, py));
    end

    # for (i = 1; i < count-2; i++) do
    1.upto(count -2 -1) do |i|
      # the first interpolated point is always the original control point
      resultArray << points[i]
      # for (j = 1; j < segments; j++) {
      1.upto(segments -1) do |j|
        pointIm1 = points[i - 1].CGPointValue
        pointI   = points[i    ].CGPointValue
        pointIp1 = points[i + 1].CGPointValue
        pointIp2 = points[i + 2].CGPointValue
        px = b[j][0]*pointIm1.x + b[j][1]*pointI.x + b[j][2]*pointIp1.x + b[j][3]*pointIp2.x;
        py = b[j][0]*pointIm1.y + b[j][1]*pointI.y + b[j][2]*pointIp1.y + b[j][3]*pointIp2.y;
        resultArray << NSValue.valueWithCGPoint(CGPointMake(px, py));
      end
    end

    i = count-2 # second to last control point
    resultArray << points[i]
    # for (int j = 1; j < segments; j++) {
    1.upto(segments - 1) do |j|
      pointIm1 = points[i - 1].CGPointValue
      pointI   = points[i    ].CGPointValue
      pointIp1 = points[i + 1].CGPointValue
      px = b[j][0]*pointIm1.x + b[j][1]*pointI.x + (b[j][2]+b[j][3])*pointIp1.x;
      py = b[j][0]*pointIm1.y + b[j][1]*pointI.y + (b[j][2]+b[j][3])*pointIp1.y;
      resultArray << NSValue.valueWithCGPoint(CGPointMake(px, py));
    end

    # the very last interpolated point is the last control point
    resultArray << points[count - 1]
    resultArray
  end

end


