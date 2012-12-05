
breed [pedestrians pedestrian]
breed [doors door]

globals [colors destinations walls pillars steps pedestrian-radius exits-count exits-count-cumulative lifespan-cumulative waiting-cumulative]

pedestrians-own [age speed target-doors ticks-waiting forced-wait-ticks]
doors-own [
  width ;; in patches
  state ;; internally kept state: 0 = closed, 1 = opening, 2 = opened, 3 = closing
  current-step ;; interal indicator of current step
  opened-for ;; time in ticks remaining before closing is started
  crowd-state ;; list [side1 side2] sides = number of ticks pedestrians should wait in distance
]
patches-own [repulsion-level]

to setup
  clear-all
  setup-layout
  setup-obstacles
  setup-destinations
  setup-steps
  setup-doors
  setup-pedestrians
  
  reset-ticks
end

to setup-obstacles
  if obstacles = "inside" or obstacles = "both" [
    ask patches with [ distance patch 10 46 <= 5] [
      set pcolor black
    ]
    ask patches with [ distance patch 10 8 <= 5] [
      set pcolor black
    ]
  ]
  
  if obstacles = "outside" or obstacles = "both" [
    ask patches with [ distance patch -35 46 <= 5] [
      set pcolor black
    ]
    ask patches with [ distance patch -35 8 <= 5] [
      set pcolor black
    ]
  ]
end

to setup-destinations
  set destinations [
    ;; color [x, y] [x, y] [allowed destinations with probability distribution 8 : 2]
    [green -70 62 -60 75 [pink blue]]
    [red -130 22 -117 32 [pink blue]]
    [blue 97 22 110 32 [green red]] 
    [pink 120 -75 130 -62 [green red]]
  ]
  
  set colors []
  foreach destinations [
    set colors fput (item 0 ?) colors
    ask patches with [
      pxcor >= item 1 ? and 
      pycor >= item 2 ? and
      pxcor <= item 3 ? and
      pycor <= item 4 ?
    ] [set pcolor item 0 ?]
  ]  
end

to setup-doors
  let corr 0
  if door-width mod 2 = 0 [set corr -0.5]
  
  ;; manual setup of door
  create-doors 1 [
    set xcor -10
    set ycor 46 + corr
  ]
  create-doors 1 [
    set xcor -10
    set ycor 9 + corr
  ]
  
  ;; shared properties
  ask doors [
    ;; visual
    set size 4
    set shape "dot"
    set color red
    
    set width door-width
    
    set state 0
    set current-step 0
    
    ;; paint door
    let y ycor
    let x xcor
    let half-width ((width - 1) / 2)
    ask patches with [pxcor = x and pycor >= floor(y - half-width) and pycor <= floor(y + half-width)] [
      set pcolor grey
    ]
    set crowd-state [0 0]
  ]
end

to setup-pedestrians
  create-pedestrians 0
  set pedestrian-radius 3
end

to go
  add-pedestrians
  age-pedestrians
  operate-doors
  ask patches with [pcolor != white and pcolor != black and count pedestrians-here > 1] [show self]
  walk
  check-crowd
  tick
end


to add-pedestrians
  let new-pedestrians-count random-poisson pedestrian-density
  
  while [new-pedestrians-count > 0] [
    let start item (random length destinations) destinations

    let clr item 0 start
    let other-clr 0
    
    ;; choose destination with distributin 8 : 2
    ifelse random 100 < 80 
      [set other-clr item 0 (item 5 start)]
      [set other-clr item 1 (item 5 start)]
      
    ask one-of patches with [pcolor = clr and far-enough? self] [
      sprout-pedestrians 1 [
        set color other-clr
        set age 0
        set size 6
        ;; 2/3 m/(half-second) ~= 4.8 km/h as a mean, 1 m = 10 patches
        set speed (random-normal (2 / 3) .25) * 10
        if speed < ((2 / 3) * 10 - 6) [set speed ((2 / 3) * 10 - 6)] ;; miniaml speed so that noone backs away
        if speed > ((2 / 3) * 10 + 6) [set speed ((2 / 3) * 10 + 6)] ;; set top limit for speed
      ]
    ]
    
    set new-pedestrians-count new-pedestrians-count - 1
  ]
end

to-report far-enough? [here]
  report count pedestrians with [distance here < pedestrian-radius] = 0
end

to age-pedestrians
  ask pedestrians [
    set age age + 1
  ]  
end

to check-crowd 
ask doors [
  
  ;; decrement crowd-states
  if item 0 crowd-state > 0 [
   set crowd-state (list (item 0 crowd-state - 1) (item 1 crowd-state)) 
  ]
  
  if item 1 crowd-state > 0 [
   set crowd-state (list (item 0 crowd-state) (item 1 crowd-state - 1)) 
  ]
  
  ;; if some pedestrian is waiting too long and
  ;; the doors are on both sides in state 0 (flow)
  if one-of pedestrians with [distance myself < 20 and ticks-waiting > 25 and determine-closest-doors self = myself] != nobody and
  item 0 crowd-state = 0 and
  item 1 crowd-state = 0 [
    ;; crowd1 = crowd from the doors left side
    let crowd1 pedestrians with [distance myself < 20 and xcor < 0]
    ;; crowd2 = crowd from the doors right side
    let crowd2 pedestrians with [distance myself < 20 and xcor > 0]
    
    ;; the bigger crowd will push through
    ;; the smaller one will recede
    ifelse count crowd1 > count crowd2 [
      ask crowd2 [
       ifelse ycor > [ycor] of myself [
        set heading 225
        bk 7 
       ][
        set heading 315
        bk 7
       ]
      ]
      set crowd-state [0 50]
    ][
      ask crowd1 [
       ifelse ycor > [ycor] of myself [
        set heading 135
        bk 7 
       ][
        set heading 45
        bk 7
       ]
      ]
      set crowd-state [50 0]
    ]
    
  ] 
]
end


to walk
  ask pedestrians [
    let continue true 
    
    if target-doors = 0 [
      set target-doors determine-closest-doors self
    ]
    
    let direct 0;
    
    ;; determine direction (head to doors, head to target)
    ifelse color = blue or color = pink [ ;; from left to right
      
      ;; if one doors are crowded from this side and the other ones are not
      if [item 0 crowd-state] of target-doors > 0 and [item 0 crowd-state] of get-other-doors self = 0 [
        set target-doors get-other-doors self
      ]
      
      ;; if both doors are crowded from this side
      ifelse [item 0 crowd-state] of target-doors > 0 and [item 0 crowd-state] of get-other-doors self > 0 [
        
        ;; in some distance the pedestrian will wait
        if distance target-doors > 3 and distance target-doors < 15 [
         set continue false 
        ]
        
        ;; in longer distances he changes his target to waiting crowd (not directly the doors)
        if distance target-doors > 10 and ycor > [ycor] of target-doors [
         set direct towardsxy ([xcor] of target-doors - 5) ([ycor] of target-doors + 5)
        ]
        if distance target-doors > 10 and ycor < [ycor] of target-doors [
         set direct towardsxy ([xcor] of target-doors - 5) ([ycor] of target-doors - 5)
        ]
      ] [
        
        ;; pedestrian continues in his direction (closest doors or his actual target)
        ifelse xcor < -12 [
          set direct towards target-doors
        ] [
          set direct direction-to-color self color
        ]
      ]
    ] [ ;; from right to left

      ;; if one doors are crowded from this side and the other ones are not
      if [item 0 crowd-state] of target-doors > 0 and [item 0 crowd-state] of get-other-doors self = 0 [
        set target-doors get-other-doors self
      ]
      
      ;; if both doors are crowded from this side
      ifelse [item 0 crowd-state] of target-doors > 0 and [item 0 crowd-state] of get-other-doors self > 0 [
        
        ;; in some distance the pedestrian will wait
        if distance target-doors > 3 and distance target-doors < 15 [
         set continue false 
        ]
        
        ;; in longer distances he changes his target to waiting crowd (not directly the doors)
        if distance target-doors > 10 and ycor > [ycor] of target-doors [
         set direct towardsxy ([xcor] of target-doors + 5) ([ycor] of target-doors + 5)
        ]
        if distance target-doors > 10 and ycor < [ycor] of target-doors [
         set direct towardsxy ([xcor] of target-doors + 5) ([ycor] of target-doors - 5)
        ]
      ] [
    
        ;; pedestrian continues in his direction (closest doors or his actual target)
        ifelse xcor > -8 [
          set direct towards target-doors
        ] [
          set direct direction-to-color self color
        ]
      ]
    ]
    
    set heading direct
    if continue = true [
    
    let angle 10
    let step 10 ;; max angle rotation
    let max-check-radius 180
     
    let zig 0
    
    let free-way-found false
    ;; if there is another pedestrian in 10 degrees radius
    ;; try to turn right by 10 degrees - if there is a pedestrian too
    ;; try to turn 20 degrees to the left
    ;; try this method until maximum of 180 (90 deg to each side)
    
    while [
      free-way-found = false and
      angle < max-check-radius
      ] [
      
      ;; lookup bound is list [a b c] according to a line equation - ax + by + c = 0
      let lookup-bounds get-lookup-bounds self
      ;;show lookup-bounds
      let line-bound1 item 0 lookup-bounds
      let line-bound2 item 1 lookup-bounds
      let x-bound1 xcor
      let ped-ycor ycor
      let x-bound2 0
      let ahead  40

      while [patch-ahead ahead = nobody and ahead > 0] [
        set ahead ahead - 1 
      ]
            
      ask patch-ahead ahead [ set x-bound2 pxcor ]
      
      if item 2 line-bound1 < item 2 line-bound2 [
       let temp line-bound1
       set line-bound1 line-bound2
       set line-bound2 temp
      ]
      
      let obstr-peds-count 0
      
      
      ask pedestrians in-cone 20 (max-check-radius) [
        if obstr-peds-count = 0 and
        xcor != x-bound1 and
        ycor != ped-ycor [
         if (item 0 line-bound1 * xcor + item 1 line-bound1 * ycor + item 2 line-bound1 >= 0 and
         item 0 line-bound2 * xcor + item 1 line-bound2 * ycor + item 2 line-bound2 <= 0 and
         xcor > x-bound1 and
         xcor < x-bound2) or 
         (item 0 line-bound1 * xcor + item 1 line-bound1 * ycor + item 2 line-bound1 <= 0 and
         item 0 line-bound2 * xcor + item 1 line-bound2 * ycor + item 2 line-bound2 >= 0 and
         xcor > x-bound1 and
         xcor < x-bound2) or
         (item 0 line-bound1 * xcor + item 1 line-bound1 * ycor + item 2 line-bound1 >= 0 and
         item 0 line-bound2 * xcor + item 1 line-bound2 * ycor + item 2 line-bound2 <= 0 and
         xcor < x-bound1 and
         xcor > x-bound2) or 
         (item 0 line-bound1 * xcor + item 1 line-bound1 * ycor + item 2 line-bound1 <= 0 and
         item 0 line-bound2 * xcor + item 1 line-bound2 * ycor + item 2 line-bound2 >= 0 and
         xcor < x-bound1 and
         xcor > x-bound2) [
           set obstr-peds-count obstr-peds-count + 1
         ]
        ]
      ]
      
      let no-obstacle true
      
      
      ;; checking of patches in a similar way as checking for obstructive pedestrians is not possible
      ;; because the algorithm is slow and cause some serious slowness in the animation
      ask patches in-cone 5 90 [
          
          if pcolor = black or pcolor = grey [
            set no-obstacle false
          ]
        
      ]
      
      ask patches in-cone 15 10 [
          
          if pcolor = black or pcolor = grey [
            set no-obstacle false
          ]
          
        
      ]
      
      
      ifelse obstr-peds-count = 0 and no-obstacle = true [
       set free-way-found true 
      ] [
        ifelse zig = 0 [
          rt angle
          set zig 1
          set angle angle + step
        ] [
          lt angle
          set zig 0
          set angle angle + step
        ]
      ]
      
    ]
      
   
    
    ;; if there is no space on the max deg radius then wait
    ifelse angle >= max-check-radius [
      ;;wait
      set heading direct
      set ticks-waiting ticks-waiting + 1
    ] [
      fd speed
      set waiting-cumulative waiting-cumulative + ticks-waiting
      set ticks-waiting 0
    ]
    
    ;;increase-radius-repulsion self
    
    let ped-color color
    ask patch-here [
      if pcolor = ped-color
        [
          set lifespan-cumulative lifespan-cumulative + [age] of myself
          set exits-count exits-count + 1
          set exits-count-cumulative exits-count-cumulative + 1
          ask myself [die]
    ]
    ]
  ]
end

to-report get-other-doors [pedestrian] 
  let current-doors [target-doors] of pedestrian
  let current-doors-ycor [ycor] of current-doors
  report one-of doors with [ycor != current-doors-ycor]
end

to-report get-lookup-bounds [pedestrian]
  
  let left-line []
  let right-line []
  
  ask pedestrian [
    let width-add 4 ;; total width = 2 * width-add + 1
    
    let ped-coors []
    let ped-xcor xcor
    let ped-ycor ycor
    let alpha heading
    
    
    let ahead 20
    while [patch-ahead ahead = nobody and ahead > 0] [
      set ahead ahead - 1 
    ]
    ask patch-ahead ahead [
     let quadrant 1 ;; four quadrants. first is x > 0 and y > 0 and clock-wise
     
     ;; calculate angle beta
     while [alpha > 90] [
       set alpha alpha - 90
       set quadrant quadrant + 1
     ]
     let beta 90 - alpha
     
     
     ;; find out extentions according the width-add
     let a cos beta * width-add
     let b sin beta * width-add
     
     ;; for quadrant 1 and 3, switch a and be - since a is to be computed with y axis and b is to be computed with x axis
     ;; for quadrant 1 and 3 there is xy: -+ +-, for quadrant 2 and for it is xy: -- ++
     if quadrant = 1 or
     quadrant = 3 [
      let temp a
      set a (- b)
      set b temp
     ]
     set a int a
     set b int b
     
     ;; create border coords for pedestrian
     let left-first-xcor ped-xcor - a
     let left-first-ycor ped-ycor - b
     
     let right-first-xcor ped-xcor + a
     let right-first-ycor ped-ycor + b
     
     ;; create helper points to determine the line equation
     let left-second-xcor pxcor - a
     let left-second-ycor pycor - b
     
     let right-second-xcor pxcor + a
     let right-second-ycor pycor + b
     
     ;; determine direction vector u=(u-1;u-2), př.: u=(1;2)
     let u-1 left-second-xcor - left-first-xcor
     let u-2 left-second-ycor - left-first-ycor
     
     ;; determine normal vector n=(n-1;n-2), př.: n=(2;-1)
     let n-1 u-2
     let n-2 u-1
     
     ifelse n-1 >= 0 [
      set n-2 (- n-2) 
     ][
      set n-1 (- n-1)
     ]
     
     ;; determine c for both lines (constant)
     let left-c ((- n-1) * left-first-xcor) - (n-2 * left-first-ycor)
     let right-c ((- n-1) * right-first-xcor) - (n-2 * right-first-ycor)
     
     ;; set lines
     set left-line (list n-1 n-2 left-c)
     set right-line (list n-1 n-2 right-c)
    ]
        
    
  ]
  report (list left-line right-line)
end

;; return list where item 0 is the doors agent closest to pedestrian and next items are coords x and y
to-report determine-closest-doors [pedestrian]
  let closest-doors 0
  ask pedestrian [ set closest-doors min-one-of doors [distance myself] ]
  report closest-doors
end

to-report get-pedestrian-ycor [pedestrian]
  let pedestrian-ycor 0
  ask pedestrian [
    set pedestrian-ycor ycor 
  ]
  
  report pedestrian-ycor
end

to-report get-pedestrian-xcor [pedestrian]
  let pedestrian-xcor 0
  ask pedestrian [
    set pedestrian-xcor xcor 
  ]
  
  report pedestrian-xcor
end

to-report direction-to-color [pedestrian clr]
  report towards min-one-of patches with [pcolor = clr] [distance pedestrian]
end

to setup-layout
  ;; prepare white canvas
  ask patches [
   set pcolor white 
    set repulsion-level 0
  ]
  
  ;; draw all walls 
  ask patches with [
    pxcor = -10 and
    pycor >= -75 and
    pycor <= 75
  ] [set pcolor black]
  
  
  ;; draw all pillars
  set pillars [
    ;; [x0 y0] r
    [-30 75 10]
    [20 81 20]
  ]
  
  foreach pillars [
    ask patches with [
      ( pxcor - item 0 ? ) ^ 2 + ( pycor - item 1 ? ) ^ 2 <= ( item 2 ? ) ^ 2 and
      ( pxcor - item 0 ? ) ^ 2 + ( pycor - item 1 ? ) ^ 2 >= ( item 2 ? - 1 ) ^ 2
    ] [set pcolor black]
  ] 
   
end

;; is in charge of changing states and firing oeprations
to operate-doors
  ask doors [    
    ifelse any? pedestrians with [distance myself <= [sensor-range] of myself]
      ;; someone nearby
      [
        ;; if closed or closing start opening
        if state = 0 or state = 3 [set state 1]
      ]
      
      ;; noone nearby
      [
        ;; if opened start closing
        if state = 2 [set state 3] 
      ]
    
    ;; fire operations
    if state = 1 [open-door self]
    if state = 3 [close-door self]
  ]
end


to open-door [door]
  ;; number of patches (to each side from center) to open
  let offset item current-step steps
  ask patches with [pycor >= [ycor] of door - offset and pxcor = [xcor] of door and pycor <= ([ycor] of door + offset) and pcolor = grey] [
    set pcolor white
  ]
        
  ifelse (current-step + 1) = length steps 
    ;; fully opened, start coundown
    [
      set state 2
      set opened-for delay-before-closing
    ]
    ;; half way through
    [set current-step current-step + 1]  
end


to close-door [door]
  ;; countdown finished
  ifelse opened-for = 0
    [
      let max-offset last steps ;; farthest patch of door
      let offset 0 ;; offset is one step before or zero
      if current-step > 0 [set offset item (current-step - 1) steps]
      
      ;; for resuse
      let x-door xcor
      let y-door floor ycor ;; deals with .5 position of door agent when width is even
      
      let correction 0 ;; correction on one side when width is even
      if remainder width 2 = 0 [set correction 1]
      
      ask patches with [
          (pxcor = x-door and pycor >= (y-door - max-offset + correction) and pycor <= (y-door - offset + correction))
          or 
          (pxcor = x-door and pycor >= (y-door + offset) and pycor <= (y-door + max-offset))
      ] [
        set pcolor grey
      ]
      
      ifelse current-step = 0
        [set state 0] ;; fully closed
        [set current-step current-step - 1] ;; still closing
    ]
    ;; counting down
    [
      set opened-for opened-for - 1
    ]
end

;; setups list of offset for door with given width and number of ticks
to setup-steps
  let half floor (door-width / 2) ;; calculates only for one side
  let odd remainder door-width 2 ;; different treatment od even and odd sized door
  let diff half / time-to-close  ;; diff between each tick
  
  if (diff < 0.5 and half > 1) [
    user-message (word "Number of ticks to open/close the door "
                       "is too high. Widen the door or shorten "
                       " the time for opening/closing.")
    stop
    clear-all
  ]
  
  let last-step 0
  let output []
  
  ;; odd sized door
  if odd = 1 [
    set last-step round diff
    ;; if door opens in more than one tick and diff is greater than one decrease the step so that it's centered
    if time-to-close > 1 and last-step > 1 [set last-step last-step - odd]
    
    set output lput last-step output
  ]
  
  ;; iterate for each tick
  repeat time-to-close - odd [
    if last-step < half [
      set last-step round (last-step + diff)
      set output lput last-step output
    ]
  ]
  
  ;; when rounding leads to door that doesn't open completely bump up middle operation and all following
  if last output < half [
    let middle-item floor ((length output) / 2)
    let inc middle-item
    repeat (length output) - middle-item [
      set output replace-item inc output (item inc output + 1)
      set inc inc + 1
    ]
  ]
  
  set steps output
end
@#$#@#$#@
GRAPHICS-WINDOW
23
264
816
748
130
75
3.0
1
10
1
1
1
0
0
0
1
-130
130
-75
75
1
1
1
ticks
30.0

BUTTON
110
45
173
78
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
110
125
173
158
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

PLOT
845
76
1045
226
pedestrians by destination
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"foreach destinations [\n    let clr item 0 ?\n    \n    create-temporary-plot-pen word \"type \" clr\n    set-current-plot-pen word \"type \" clr\n    set-plot-pen-color clr\n  ]" "foreach destinations [\n    let clr item 0 ?\n    \n    set-current-plot-pen word \"type \" clr\n    plot count pedestrians with [color = clr]\n  ]"
PENS

PLOT
847
279
1047
429
avg pedestrian age
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"foreach destinations [\n    let clr item 0 ?\n    \n    create-temporary-plot-pen word \"type \" clr\n    set-current-plot-pen word \"type \" clr\n    set-plot-pen-color clr\n  ]" "foreach destinations [\n  let clr item 0 ?  \n  set-current-plot-pen word \"type \" clr\n    \n  let current-ped pedestrians with [color = clr]\n  ifelse any? current-ped\n    [plot mean [age] of current-ped]\n    [plot 0]\n]"
PENS
"pen-0" 1.0 0 -16448764 true "" "ifelse any? pedestrians\n[plot mean [age] of pedestrians]\n[plot 0]"

BUTTON
105
85
180
118
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
220
45
410
78
delay-before-closing
delay-before-closing
0
10
0
1
1
ticks
HORIZONTAL

SLIDER
220
90
410
123
time-to-close
time-to-close
1
22
11
1
1
ticks
HORIZONTAL

SLIDER
220
135
410
168
sensor-range
sensor-range
3
20
8
1
1
patches
HORIZONTAL

SLIDER
220
180
410
213
door-width
door-width
7
25
21
1
1
NIL
HORIZONTAL

PLOT
1110
80
1310
230
avg pedestrian speed
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot (20 / 3)"
"pen-1" 1.0 0 -5825686 true "" "ifelse any? pedestrians\n[plot mean [speed] of pedestrians]\n[plot 0]"

SLIDER
420
45
592
78
pedestrian-density
pedestrian-density
.25
1
1
.05
1
NIL
HORIZONTAL

CHOOSER
425
170
563
215
obstacles
obstacles
"none" "inside" "outside" "both"
0

PLOT
1085
255
1285
405
exits 
NIL
NIL
0.0
10.0
0.0
5.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot exits-count\nset exits-count 0"

MONITOR
615
15
735
60
exits per tick
precision (exits-count-cumulative / ticks) 3
17
1
11

MONITOR
615
75
735
120
avg age of pedestrians
precision (lifespan-cumulative / exits-count-cumulative) 2
17
1
11

MONITOR
615
130
777
175
ratio of waiting pedestrians
precision (count pedestrians with [ticks-waiting > 0] / count pedestrians) 2
17
1
11

MONITOR
615
185
717
230
avg waiting time
precision (waiting-cumulative / exits-count-cumulative) 2
17
1
11

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.0.3
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 1.0 0.0
0.0 1 1.0 0.0
0.2 0 1.0 0.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
1
@#$#@#$#@
