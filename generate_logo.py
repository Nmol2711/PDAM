def create_perfect_curved_svg(filename="logo.svg"):
    svg_content = '''<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg
   width="512"
   height="512"
   viewBox="0 0 512 512"
   version="1.1"
   id="svg_logo"
   xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
   xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"
   xmlns:xlink="http://www.w3.org/1999/xlink"
   xmlns="http://www.w3.org/2000/svg"
   xmlns:svg="http://www.w3.org/2000/svg">
  <defs id="defs1">
    <!-- Background Radial Gradient: Vibrant modern purple -->
    <radialGradient
       id="bgGradient"
       cx="256"
       cy="220"
       r="240"
       fx="256"
       fy="200"
       gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#A855F7" />
      <stop offset="40%" stop-color="#7E22CE" />
      <stop offset="75%" stop-color="#581C87" />
      <stop offset="100%" stop-color="#3B0764" />
    </radialGradient>

    <!-- Top Stroke Gradient: Bright Electric Cyan-Blue -->
    <linearGradient
       id="topStrokeGradient"
       x1="120"
       y1="100"
       x2="400"
       y2="260"
       gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#38BDF8" />
      <stop offset="50%" stop-color="#0EA5E9" />
      <stop offset="100%" stop-color="#0284C7" />
    </linearGradient>

    <!-- Bottom Stroke Gradient -->
    <linearGradient
       id="bottomStrokeGradient"
       x1="180"
       y1="340"
       x2="340"
       y2="420"
       gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#7DD3FC" />
      <stop offset="100%" stop-color="#0284C7" />
    </linearGradient>
  </defs>

  <sodipodi:namedview
     id="namedview1"
     pagecolor="#ffffff"
     bordercolor="#000000"
     borderopacity="0.25"
     inkscape:showpageshadow="2"
     inkscape:pageopacity="0.0"
     inkscape:pagecheckerboard="0"
     inkscape:deskcolor="#d1d1d1"
     inkscape:document-units="px"
     showgrid="false" />

  <!-- Layer 1: Fondo (Background Container) -->
  <g
     inkscape:groupmode="layer"
     id="layer_fondo"
     inkscape:label="Fondo">
    <circle
       id="bg_circle"
       cx="256"
       cy="256"
       r="220"
       fill="url(#bgGradient)" />
  </g>

  <!-- Layer 2: Trazos Internos (Moved up top, smaller bottom, perfectly contouring circle) -->
  <g
     inkscape:groupmode="layer"
     id="layer_trazos"
     inkscape:label="Trazos Internos">

    <!-- Trazo Superior (Subido ligeramente más arriba, siguiendo perfectamente el contorno superior con garras a la izquierda) -->
    <path
       id="trazo_superior"
       fill="url(#topStrokeGradient)"
       d="M 130 190
          C 125 175 140 165 153 160
          L 140 142
          C 147 132 165 125 180 120
          L 165 105
          C 195 90 230 85 265 90
          C 335 100 405 150 425 215
          C 432 240 425 265 410 288
          C 395 262 380 232 350 205
          C 305 165 225 152 165 168
          C 150 173 137 182 130 190
          Z" />

    <!-- Trazo Inferior (Más pequeño, sutil y estilizado, siguiendo la curva inferior con garras a la derecha) -->
    <path
       id="trazo_inferior"
       fill="url(#bottomStrokeGradient)"
       d="M 370 320
          C 375 332 362 342 350 347
          L 362 362
          C 355 370 340 377 327 382
          L 337 395
          C 312 405 285 408 260 405
          C 200 398 145 365 125 315
          C 120 302 125 288 138 275
          C 150 292 162 310 188 328
          C 225 352 285 362 332 345
          C 345 340 358 330 370 320
          Z" />
  </g>
</svg>
'''
    with open(filename, "w") as f:
        f.write(svg_content)

create_perfect_curved_svg()
