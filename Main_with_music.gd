
extends Node2D

enum GameState { MENU, PLAYING, PAUSED, DEAD }

const BASE_VIEW := Vector2i(1280, 720)
const GRAVITY := 1750.0
const JUMP_FORCE := -680.0
const PLAYER_SIZE := 38.0
const CHASE_INTERVAL := 30.0
const CHASE_DURATION := 14.0
const SAMPLE_RATE := 22050

var rng := RandomNumberGenerator.new()
var state = GameState.MENU
var mode = "CUBE"

var player_y := 0.0
var velocity_y := 0.0
var rotation_angle := 0.0
var grounded := true

var elapsed := 0.0
var distance := 0.0
var score := 0
var best := 0
var base_speed := 410.0
var speed := 410.0

var obstacles: Array[Dictionary] = []
var spawn_timer := 0.0

var chase_active := false
var chase_timer := 0.0
var next_chase_time := CHASE_INTERVAL
var police_x := -200.0

var flash := 0.0
var menu_time := 0.0
var pressed_space := false
var jump_requested := false

var audio_players: Array[AudioStreamPlayer] = []
var audio_cursor := 0
var siren_timer := 0.0
var rocket_sound_timer := 0.0
var music_player: AudioStreamPlayer
var normal_music: AudioStreamWAV
var chase_music: AudioStreamWAV


func _ready():
    rng.randomize()

    var window = get_window()
    window.unresizable = false
    window.borderless = false
    window.min_size = Vector2i(800, 450)
    window.size = BASE_VIEW
    window.mode = Window.MODE_WINDOWED
    window.content_scale_size = BASE_VIEW
    window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
    window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

    for i in range(8):
        var p := AudioStreamPlayer.new()
        p.volume_db = -5.0
        add_child(p)
        audio_players.append(p)

    # Отдельный музыкальный плеер — эффекты игры остаются без изменений.
    music_player = AudioStreamPlayer.new()
    music_player.volume_db = -13.0
    add_child(music_player)
    normal_music = make_music(false)
    chase_music = make_music(true)

    if FileAccess.file_exists("user://best.save"):
        var file = FileAccess.open("user://best.save", FileAccess.READ)
        if file:
            best = int(file.get_var())

    player_y = ground_y() - PLAYER_SIZE
    queue_redraw()


# ==========================================
# SOUND GENERATOR
# ==========================================

func make_tone(freq: float, duration: float, volume: float,
        shape: String = "sine", sweep: float = 0.0) -> AudioStreamWAV:

    var count := maxi(1, int(SAMPLE_RATE * duration))
    var bytes := PackedByteArray()
    bytes.resize(count * 2)

    for i in range(count):
        var t := float(i) / SAMPLE_RATE
        var progress := float(i) / float(count)
        var f := maxf(30.0, freq + sweep * progress)
        var phase := TAU * f * t
        var sample := 0.0

        if shape == "noise":
            sample = rng.randf_range(-1.0, 1.0)
        elif shape == "square":
            sample = 1.0 if sin(phase) >= 0.0 else -1.0
        elif shape == "saw":
            sample = 2.0 * fmod(f * t, 1.0) - 1.0
        else:
            sample = sin(phase)

        var fade_in := minf(1.0, float(i) / 180.0)
        var fade_out := minf(1.0, float(count - i) / 500.0)
        var value := clampf(sample * volume * minf(fade_in, fade_out), -1.0, 1.0)

        bytes.encode_s16(i * 2, int(value * 32767.0))

    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = SAMPLE_RATE
    wav.stereo = false
    wav.data = bytes
    return wav


func play_sfx(freq: float, duration: float, volume: float,
        shape: String = "sine", sweep: float = 0.0):

    var p = audio_players[audio_cursor]
    audio_cursor = (audio_cursor + 1) % audio_players.size()

    p.stop()
    p.stream = make_tone(freq, duration, volume, shape, sweep)
    p.play()


func play_switch_sound():
    play_sfx(520.0, 0.10, 0.18, "sine", 360.0)


func play_jump_sound():
    play_sfx(330.0, 0.13, 0.20, "sine", 430.0)


func play_crash_sound():
    play_sfx(105.0, 0.42, 0.32, "saw", -65.0)
    play_sfx(55.0, 0.30, 0.22, "noise")


func play_chase_sound():
    play_sfx(620.0, 0.24, 0.24, "square", 260.0)
    play_sfx(880.0, 0.30, 0.22, "square", -240.0)


# ORIGINAL PROCEDURAL EDM MUSIC
# Музыка генерируется прямо в игре, внешние файлы не нужны.
func make_music(chase_version: bool) -> AudioStreamWAV:
    var duration := 8.0
    var count := int(SAMPLE_RATE * duration)
    var bytes := PackedByteArray()
    bytes.resize(count * 2)

    var bass_notes := [55.0, 65.41, 73.42, 49.0]
    var lead_notes := [220.0, 261.63, 329.63, 392.0, 329.63, 293.66, 261.63, 196.0]

    for i in range(count):
        var t := float(i) / float(SAMPLE_RATE)
        var bar := int(t / 2.0) % 4
        var step := int(t * 4.0) % 8
        var bass_freq: float = bass_notes[bar]
        var lead_freq: float = lead_notes[step]

        var bass := sin(TAU * bass_freq * t) * 0.20
        bass += sin(TAU * bass_freq * 2.0 * t) * 0.055

        var lead := sin(TAU * lead_freq * t) * 0.075
        lead += sin(TAU * lead_freq * 2.0 * t) * 0.025

        var beat_pos := fmod(t, 0.5)
        var kick := 0.0
        if beat_pos < 0.15:
            kick = sin(TAU * (95.0 - beat_pos * 300.0) * t) * exp(-beat_pos * 25.0) * 0.48

        var snare := 0.0
        var half_pos := fmod(t, 1.0)
        if half_pos > 0.48 and half_pos < 0.60:
            snare = rng.randf_range(-1.0, 1.0) * exp(-(half_pos - 0.48) * 28.0) * 0.13

        var hat := 0.0
        var hat_pos := fmod(t, 0.25)
        if hat_pos < 0.025:
            hat = rng.randf_range(-1.0, 1.0) * (1.0 - hat_pos / 0.025) * 0.07

        var value := bass + lead + kick + snare + hat
        if chase_version:
            value = bass * 0.85 + lead * 1.35 + kick * 1.15 + snare + hat * 1.7

        value = clampf(value, -0.95, 0.95)
        bytes.encode_s16(i * 2, int(value * 32767.0))

    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = SAMPLE_RATE
    wav.stereo = false
    wav.data = bytes
    wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
    wav.loop_begin = 0
    wav.loop_end = count
    return wav


func play_game_music(chase_version: bool = false):
    if music_player == null:
        return
    music_player.stop()
    music_player.stream = chase_music if chase_version else normal_music
    music_player.play()


# ROCKET FIRE SOUND
func play_rocket_thrust():
    play_sfx(95.0, 0.20, 0.22, "noise", -18.0)
    play_sfx(125.0, 0.18, 0.10, "saw", 55.0)


# ==========================================
# SCREEN
# ==========================================

func ground_y() -> float:
    return get_viewport_rect().size.y * 0.82


func player_x() -> float:
    return get_viewport_rect().size.x * 0.19


func toggle_fullscreen():
    if get_window().mode == Window.MODE_FULLSCREEN:
        get_window().mode = Window.MODE_WINDOWED
    else:
        get_window().mode = Window.MODE_FULLSCREEN


# ==========================================
# MODES
# ==========================================

func change_mode(new_mode: String):
    if state != GameState.PLAYING or mode == new_mode:
        return

    mode = new_mode
    velocity_y = 0.0
    rotation_angle = 0.0
    grounded = false
    rocket_sound_timer = 0.0
    play_switch_sound()


# ==========================================
# INPUT
# ==========================================

func _input(event):

    if event is InputEventKey:

        if event.keycode == KEY_F11 and event.pressed and not event.echo:
            toggle_fullscreen()
            return

        if event.keycode == KEY_SPACE or event.keycode == KEY_UP:
            pressed_space = event.pressed
            if event.pressed and not event.echo:
                jump_requested = true

        if not event.pressed or event.echo:
            return

        if state == GameState.PLAYING:

            if event.keycode == KEY_Q:
                change_mode("CUBE")
            elif event.keycode == KEY_W:
                change_mode("SHIP")
            elif event.keycode == KEY_E:
                change_mode("ROCKET_UP")
            elif event.keycode == KEY_ESCAPE:
                state = GameState.PAUSED
                pressed_space = false
                if music_player != null:
                    music_player.stream_paused = true

        elif state == GameState.PAUSED:

            if event.keycode == KEY_ESCAPE:
                state = GameState.PLAYING
                if music_player != null:
                    music_player.stream_paused = false

            elif event.keycode == KEY_R:
                state = GameState.MENU
                if music_player != null:
                    music_player.stop()

        elif state == GameState.DEAD:

            if event.keycode == KEY_R:
                start_game()

    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:

            if event.pressed:
                var handled = handle_click(event.position)

                if not handled and state == GameState.PLAYING:
                    pressed_space = true
                    jump_requested = true
            else:
                pressed_space = false


func handle_click(pos: Vector2) -> bool:
    var s = get_viewport_rect().size
    var center = s.x / 2.0

    if state == GameState.MENU:

        var y = s.y * 0.48

        if Rect2(center - 145, y, 290, 58).has_point(pos):
            start_game()
            return true

        if Rect2(center - 145, y + 72, 290, 48).has_point(pos):
            if mode == "CUBE":
                mode = "SHIP"
            elif mode == "SHIP":
                mode = "ROCKET_UP"
            else:
                mode = "CUBE"

            return true

        if Rect2(center - 145, y + 133, 290, 42).has_point(pos):
            toggle_fullscreen()
            return true

    elif state == GameState.PLAYING:

        if Rect2(s.x - 370, 58, 110, 44).has_point(pos):
            change_mode("CUBE")
            return true

        if Rect2(s.x - 252, 58, 110, 44).has_point(pos):
            change_mode("SHIP")
            return true

        if Rect2(s.x - 134, 58, 120, 44).has_point(pos):
            change_mode("ROCKET_UP")
            return true

    elif state == GameState.PAUSED:

        if Rect2(center - 140, s.y / 2.0 + 20, 280, 55).has_point(pos):
            state = GameState.PLAYING
            if music_player != null:
                music_player.stream_paused = false
            return true

        if Rect2(center - 140, s.y / 2.0 + 90, 280, 55).has_point(pos):
            state = GameState.MENU
            if music_player != null:
                music_player.stop()
            return true

    elif state == GameState.DEAD:

        if Rect2(center - 140, s.y * 0.58, 280, 55).has_point(pos):
            start_game()
            return true

    return false


# ==========================================
# GAME START
# ==========================================

func start_game():
    state = GameState.PLAYING

    elapsed = 0.0
    distance = 0.0
    score = 0
    speed = base_speed

    mode = "CUBE"
    velocity_y = 0.0
    rotation_angle = 0.0
    grounded = true

    player_y = ground_y() - PLAYER_SIZE

    obstacles.clear()
    spawn_timer = 1.0

    chase_active = false
    chase_timer = 0.0
    next_chase_time = CHASE_INTERVAL
    police_x = -200.0

    flash = 0.0
    pressed_space = false
    jump_requested = false
    siren_timer = 0.0
    rocket_sound_timer = 0.0

    play_sfx(440.0, 0.16, 0.18, "sine", 440.0)
    play_game_music(false)


func spawn_obstacle():
    var kind = rng.randi_range(0, 7)
    var g = ground_y()

    var obstacle: Dictionary = {
        "kind": kind,
        "x": get_viewport_rect().size.x + 100.0,
        "width": 42.0,
        "height": rng.randf_range(48.0, 68.0),
        "angle": 0.0,
        "gap_y": rng.randf_range(90.0, max(100.0, g - 260.0)),
        "gap": 180.0,
        "drone_y": rng.randf_range(120.0, max(160.0, g - 100.0))
    }

    if kind == 1:
        obstacle["width"] = 84.0
    elif kind == 2:
        obstacle["width"] = 126.0
    elif kind == 3:
        obstacle["width"] = 52.0
        obstacle["height"] = 70.0
    elif kind == 4:
        obstacle["width"] = 58.0
        obstacle["height"] = 58.0
    elif kind == 5:
        obstacle["width"] = 65.0
    elif kind == 6:
        obstacle["width"] = 55.0
    elif kind == 7:
        obstacle["width"] = 70.0

    obstacles.append(obstacle)


# ==========================================
# POLICE CHASE
# ==========================================

func start_chase():
    chase_active = true
    chase_timer = CHASE_DURATION
    police_x = player_x() - 250.0
    flash = 1.0
    siren_timer = 0.0

    play_chase_sound()
    play_game_music(true)


func end_chase():
    chase_active = false
    chase_timer = 0.0
    police_x = -200.0

    play_sfx(520.0, 0.25, 0.20, "sine", -350.0)
    if state == GameState.PLAYING:
        play_game_music(false)


func die():
    if state == GameState.DEAD:
        return

    state = GameState.DEAD
    pressed_space = false
    flash = 0.7

    play_crash_sound()
    if music_player != null:
        music_player.stop()

    if score > best:
        best = score

        var file = FileAccess.open("user://best.save", FileAccess.WRITE)
        if file != null:
            file.store_var(best)


# ==========================================
# GAME LOOP
# ==========================================

func _process(delta):

    menu_time += delta
    flash = move_toward(flash, 0.0, delta * 2.0)

    if state != GameState.PLAYING:
        rocket_sound_timer = 0.0
        queue_redraw()
        return

    elapsed += delta

    # POLICE EVERY 30 SECONDS
    if not chase_active and elapsed >= next_chase_time:
        start_chase()
        next_chase_time += CHASE_INTERVAL

    # CONTINUOUS ROCKET FLAME SOUND WHILE SPACE IS HELD
    if mode == "ROCKET_UP" and pressed_space:
        rocket_sound_timer -= delta

        if rocket_sound_timer <= 0.0:
            play_rocket_thrust()
            rocket_sound_timer = 0.14
    else:
        rocket_sound_timer = 0.0

    # POLICE SIREN
    if chase_active:

        chase_timer -= delta
        siren_timer -= delta

        if siren_timer <= 0.0:
            play_chase_sound()
            siren_timer = 0.85

        police_x = move_toward(
            police_x,
            player_x() - 95.0,
            delta * 35.0
        )

        if chase_timer <= 0.0:
            end_chase()

    # SPEED
    speed = base_speed * (4.0 if chase_active else 1.0)

    distance += speed * delta
    score = int(distance / 10.0)

    var g = ground_y()

    # CUBE
    if mode == "CUBE":

        if jump_requested and grounded:
            velocity_y = JUMP_FORCE
            grounded = false
            play_jump_sound()

        velocity_y += GRAVITY * delta
        player_y += velocity_y * delta

        if player_y >= g - PLAYER_SIZE:
            player_y = g - PLAYER_SIZE
            velocity_y = 0.0
            grounded = true

            rotation_angle = round(
                rotation_angle / (PI / 2.0)
            ) * (PI / 2.0)

        else:
            grounded = false
            rotation_angle += delta * TAU * 1.5

    # SHIP
    elif mode == "SHIP":

        velocity_y += GRAVITY * delta

        if pressed_space:
            velocity_y -= 3000.0 * delta

        velocity_y = clamp(velocity_y, -700.0, 700.0)

        player_y += velocity_y * delta
        player_y = clamp(player_y, 30.0, g - PLAYER_SIZE)

        rotation_angle = clamp(
            velocity_y / 1100.0,
            -0.55,
            0.55
        )

    # VERTICAL ROCKET
    elif mode == "ROCKET_UP":

        velocity_y += GRAVITY * delta

        if pressed_space:
            velocity_y -= 4200.0 * delta

        velocity_y = clamp(velocity_y, -1000.0, 800.0)

        player_y += velocity_y * delta
        player_y = clamp(player_y, 30.0, g - PLAYER_SIZE)

        rotation_angle = 0.0

    jump_requested = false

    # OBSTACLES
    spawn_timer -= delta

    if spawn_timer <= 0.0:
        spawn_obstacle()

        if chase_active:
            spawn_timer = rng.randf_range(0.9, 1.2)
        else:
            spawn_timer = rng.randf_range(1.2, 1.8)

    # COLLISION
    var player_rect = Rect2(
        player_x() - PLAYER_SIZE / 2.0 + 6.0,
        player_y + 6.0,
        PLAYER_SIZE - 12.0,
        PLAYER_SIZE - 12.0
    )

    for obstacle in obstacles:

        obstacle["x"] -= speed * delta
        obstacle["angle"] += delta * 4.0

        var x = obstacle["x"]
        var w = obstacle["width"]
        var h = obstacle["height"]
        var kind = obstacle["kind"]

        if kind == 7:

            var gy = obstacle["gap_y"]
            var gap = obstacle["gap"]

            if player_rect.intersects(Rect2(x, 0, w, gy)):
                die()

            if player_rect.intersects(
                Rect2(x, gy + gap, w, max(0.0, g - gy - gap))
            ):
                die()

        elif kind == 5:

            if player_rect.intersects(Rect2(x + 5, 0, w - 10, h - 10)):
                die()

        elif kind == 6:

            if player_rect.intersects(
                Rect2(x + 5, obstacle["drone_y"], w - 10, 35)
            ):
                die()

        else:

            if player_rect.intersects(
                Rect2(x + 5, g - h + 8, w - 10, h - 8)
            ):
                die()

    obstacles = obstacles.filter(
        func(o): return o["x"] > -200.0
    )

    queue_redraw()


# ==========================================
# DRAW HELPERS
# ==========================================

func draw_text_center(message: String, y: float, font_size: int, color: Color):
    var w = get_viewport_rect().size.x

    draw_string(
        ThemeDB.fallback_font,
        Vector2(0, y),
        message,
        HORIZONTAL_ALIGNMENT_CENTER,
        w,
        font_size,
        color
    )


func draw_button(rect: Rect2, label: String, selected: bool = false):
    var fill = Color("#171a2a")
    var outline = Color("#38435d")

    if selected:
        fill = Color("#142c3b")
        outline = Color("#00dfff")

    draw_rect(rect, fill)
    draw_rect(rect, outline, false, 2.0)

    draw_string(
        ThemeDB.fallback_font,
        Vector2(
            rect.position.x,
            rect.position.y + rect.size.y / 2.0 + 7.0
        ),
        label,
        HORIZONTAL_ALIGNMENT_CENTER,
        rect.size.x,
        17,
        Color.WHITE
    )


# ==========================================
# MAIN RENDER
# ==========================================

func _draw():

    var s = get_viewport_rect().size
    var w = s.x
    var h = s.y

    draw_rect(Rect2(Vector2.ZERO, s), Color("#080a14"))

    var offset = fmod(distance * 0.25 + menu_time * 12.0, 70.0)

    for x in range(-70, int(w) + 70, 70):
        draw_line(
            Vector2(x - offset, 0),
            Vector2(x - offset, h),
            Color(0.0, 0.7, 1.0, 0.09),
            1.0
        )

    for y in range(0, int(h), 70):
        draw_line(
            Vector2(0, y),
            Vector2(w, y),
            Color(0.0, 0.7, 1.0, 0.09),
            1.0
        )

    if state == GameState.MENU:
        draw_menu(w, h)
        return

    var g = ground_y()
    var shake = Vector2.ZERO

    if chase_active:
        shake = Vector2(
            sin(menu_time * 60.0) * 5.0,
            cos(menu_time * 75.0) * 4.0
        )

    draw_set_transform(shake, 0.0, Vector2.ONE)

    draw_rect(
        Rect2(0, g, w, h - g),
        Color("#11172b")
    )

    draw_line(
        Vector2(0, g),
        Vector2(w, g),
        Color("#00dfff"),
        3.0
    )

    for x in range(-100, int(w) + 100, 70):
        var fx = x - fmod(distance * 0.8, 70.0)

        draw_line(
            Vector2(fx, g + 20),
            Vector2(fx - 30, h),
            Color(0.0, 0.8, 1.0, 0.15),
            2.0
        )

    for obstacle in obstacles:
        draw_obstacle(obstacle, g)

    draw_player()

    if chase_active:
        draw_police_car(police_x, g - 38.0)

    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

    draw_hud(w, h)

    if state == GameState.PAUSED:

        draw_overlay("PAUSED", "ESCAPE TO CONTINUE")

        draw_button(
            Rect2(w / 2.0 - 140, h / 2.0 + 20, 280, 55),
            "RESUME",
            true
        )

        draw_button(
            Rect2(w / 2.0 - 140, h / 2.0 + 90, 280, 55),
            "MAIN MENU"
        )

    if state == GameState.DEAD:

        draw_overlay(
            "RUN TERMINATED",
            "FINAL SCORE: " + str(score)
        )

        draw_button(
            Rect2(w / 2.0 - 140, h * 0.58, 280, 55),
            "RETRY",
            true
        )

    if flash > 0.1:
        draw_rect(
            Rect2(Vector2.ZERO, s),
            Color(1, 0, 0, flash * 0.1)
        )


# ==========================================
# MENU
# ==========================================

func draw_menu(w: float, h: float):

    for i in range(5):
        var radius = 110.0 + i * 35.0

        draw_arc(
            Vector2(w / 2.0, h * 0.27),
            radius,
            menu_time * 0.15 + i,
            menu_time * 0.15 + i + PI,
            64,
            Color(0.0, 0.8, 1.0, 0.10),
            2.0
        )

    draw_text_center(
        "N / D     INTERACTIVE SYSTEMS",
        h * 0.11,
        15,
        Color("#6f829e")
    )

    draw_text_center(
        "NEON DASH",
        h * 0.27,
        66,
        Color("#f0f7ff")
    )

    draw_text_center(
        "UNDERGROUND",
        h * 0.34,
        20,
        Color("#00dfff")
    )

    draw_line(
        Vector2(w / 2.0 - 140, h * 0.39),
        Vector2(w / 2.0 + 140, h * 0.39),
        Color("#00dfff"),
        2.0
    )

    var center = w / 2.0
    var y = h * 0.48

    draw_button(Rect2(center - 145, y, 290, 58), "START GAME", true)
    draw_button(Rect2(center - 145, y + 72, 290, 48), "MODE / " + mode)
    draw_button(Rect2(center - 145, y + 133, 290, 42), "FULLSCREEN / F11")

    draw_text_center(
        "Q CUBE    W SHIP    E ROCKET    SPACE FLIGHT",
        h - 55,
        14,
        Color("#73839d")
    )

    draw_text_center(
        "POLICE CHAOS EVERY 30 SECONDS // RECORD " + str(best),
        h - 27,
        13,
        Color("#53627a")
    )


# ==========================================
# OBSTACLES
# ==========================================

func draw_obstacle(o: Dictionary, g: float):

    var x = o["x"]
    var w = o["width"]
    var h = o["height"]
    var kind = o["kind"]

    if kind <= 2:

        for i in range(kind + 1):
            var sx = x + i * 42.0

            var points = PackedVector2Array([
                Vector2(sx, g),
                Vector2(sx + 21, g - h),
                Vector2(sx + 42, g)
            ])

            draw_colored_polygon(points, Color("#ff315d"))
            draw_polyline(points, Color.WHITE, 2.0)

    elif kind == 3:

        draw_rect(Rect2(x, g - h, w, h), Color("#922dff"))
        draw_rect(Rect2(x + 5, g - h + 5, w - 10, h - 10), Color("#25143e"))
        draw_rect(Rect2(x, g - h, w, h), Color("#d5a0ff"), false, 2.0)

    elif kind == 4:

        var center = Vector2(x + w / 2.0, g - h / 2.0)
        var points = PackedVector2Array()

        for i in range(20):
            var radius = 29.0 if i % 2 == 0 else 21.0
            var a = i * TAU / 20.0 + o["angle"]
            points.append(center + Vector2.RIGHT.rotated(a) * radius)

        draw_colored_polygon(points, Color("#ffb52e"))
        draw_circle(center, 13.0, Color("#361b2a"))
        draw_circle(center, 5.0, Color.WHITE)

    elif kind == 5:

        draw_colored_polygon(
            PackedVector2Array([
                Vector2(x, 0),
                Vector2(x + w / 2.0, h),
                Vector2(x + w, 0)
            ]),
            Color("#ff315d")
        )

    elif kind == 6:

        var center = Vector2(x + w / 2.0, o["drone_y"] + 18.0)

        draw_circle(center, 22.0, Color("#a42aff"))
        draw_circle(center, 9.0, Color("#ff315d"))
        draw_circle(center, 4.0, Color.WHITE)

        draw_line(
            center + Vector2(-32, 0),
            center + Vector2(32, 0),
            Color("#00eaff"),
            3.0
        )

    elif kind == 7:

        var gy = o["gap_y"]
        var gap = o["gap"]

        draw_rect(Rect2(x, 0, w, gy), Color("#912aff"))

        draw_rect(
            Rect2(x, gy + gap, w, max(0.0, g - gy - gap)),
            Color("#912aff")
        )

        draw_rect(Rect2(x, gy - 4, w, 4), Color("#ff315d"))
        draw_rect(Rect2(x, gy + gap, w, 4), Color("#ff315d"))


# ==========================================
# PLAYER DRAW
# ==========================================

func draw_player():

    if state == GameState.DEAD:
        return

    var center = Vector2(
        player_x(),
        player_y + PLAYER_SIZE / 2.0
    )

    draw_set_transform(center, rotation_angle, Vector2.ONE)

    if mode == "CUBE":

        draw_rect(Rect2(-22, -22, 44, 44), Color(0, 0.8, 1, 0.15))
        draw_rect(Rect2(-19, -19, 38, 38), Color("#00dfff"))
        draw_rect(Rect2(-12, -12, 24, 24), Color.WHITE)
        draw_rect(Rect2(-7, -7, 14, 14), Color("#1263d8"))

    elif mode == "SHIP":

        draw_colored_polygon(
            PackedVector2Array([
                Vector2(-27, 0),
                Vector2(-8, -9),
                Vector2(12, -8),
                Vector2(28, 0),
                Vector2(12, 8),
                Vector2(-8, 9)
            ]),
            Color("#00dfff")
        )

        draw_colored_polygon(
            PackedVector2Array([
                Vector2(-5, -6),
                Vector2(5, -23),
                Vector2(15, -23),
                Vector2(12, 0),
                Vector2(15, 23),
                Vector2(5, 23),
                Vector2(-5, 6)
            ]),
            Color.WHITE
        )

        draw_circle(Vector2(12, 0), 4, Color("#1263d8"))

        if pressed_space:
            draw_colored_polygon(
                PackedVector2Array([
                    Vector2(-24, -5),
                    Vector2(-48, 0),
                    Vector2(-24, 5)
                ]),
                Color("#ff9b32")
            )

    elif mode == "ROCKET_UP":

        draw_colored_polygon(
            PackedVector2Array([
                Vector2(0, -30),
                Vector2(12, -8),
                Vector2(10, 17),
                Vector2(-10, 17),
                Vector2(-12, -8)
            ]),
            Color("#f0f5ff")
        )

        draw_colored_polygon(
            PackedVector2Array([
                Vector2(-10, 8),
                Vector2(-23, 22),
                Vector2(-10, 18)
            ]),
            Color("#00dfff")
        )

        draw_colored_polygon(
            PackedVector2Array([
                Vector2(10, 8),
                Vector2(23, 22),
                Vector2(10, 18)
            ]),
            Color("#00dfff")
        )

        draw_circle(Vector2(0, -5), 6, Color("#00dfff"))

        if pressed_space:
            draw_colored_polygon(
                PackedVector2Array([
                    Vector2(-6, 17),
                    Vector2(0, 42),
                    Vector2(6, 17)
                ]),
                Color("#ff9b32")
            )

    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ==========================================
# POLICE CAR
# ==========================================

func draw_police_car(x: float, y: float):

    draw_rect(Rect2(x, y, 100, 30), Color("#171b2d"))
    draw_rect(Rect2(x + 15, y - 16, 60, 19), Color("#293b5c"))

    draw_rect(Rect2(x + 23, y - 12, 20, 12), Color("#00cfff"))
    draw_rect(Rect2(x + 48, y - 12, 20, 12), Color("#00cfff"))

    draw_circle(Vector2(x + 23, y + 29), 9, Color.BLACK)
    draw_circle(Vector2(x + 76, y + 29), 9, Color.BLACK)

    var red = Color("#ff1744")
    var blue = Color("#00eaff")

    if int(Time.get_ticks_msec() / 100.0) % 2 == 0:
        draw_rect(Rect2(x + 27, y - 23, 19, 7), red)
        draw_rect(Rect2(x + 50, y - 23, 19, 7), blue)
    else:
        draw_rect(Rect2(x + 27, y - 23, 19, 7), blue)
        draw_rect(Rect2(x + 50, y - 23, 19, 7), red)


# ==========================================
# HUD
# ==========================================

func draw_hud(w: float, h: float):

    var accent = Color("#ff315d") if chase_active else Color("#00dfff")

    draw_string(
        ThemeDB.fallback_font,
        Vector2(25, 35),
        "NEON DASH / UNDERGROUND",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 18, accent
    )

    draw_string(
        ThemeDB.fallback_font,
        Vector2(25, 65),
        "SCORE " + str(score),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE
    )

    draw_string(
        ThemeDB.fallback_font,
        Vector2(25, 90),
        "BEST " + str(best),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#9baac5")
    )

    draw_button(Rect2(w - 370, 58, 110, 44), "Q / CUBE", mode == "CUBE")
    draw_button(Rect2(w - 252, 58, 110, 44), "W / SHIP", mode == "SHIP")
    draw_button(Rect2(w - 134, 58, 120, 44), "E / ROCKET", mode == "ROCKET_UP")

    if chase_active:

        var siren = Color("#ff315d")

        if int(menu_time * 8.0) % 2 == 0:
            siren = Color("#00dfff")

        draw_rect(Rect2(0, 0, w, 7), siren)
        draw_rect(Rect2(0, h - 7, w, 7), siren)

        draw_text_center(
            "POLICE PURSUIT // SPEED x4",
            h * 0.22,
            28,
            siren
        )

        draw_text_center(
            "ESCAPE THE CHAOS",
            h * 0.28,
            18,
            Color.WHITE
        )

        for i in range(8):
            var line_y = fmod(
                menu_time * (120.0 + i * 13.0) + i * 91.0,
                h
            )

            draw_rect(
                Rect2(0, line_y, w, 2),
                Color(1, 0, 0.4, 0.18)
            )


func draw_overlay(title: String, subtitle: String):

    var s = get_viewport_rect().size

    draw_rect(
        Rect2(Vector2.ZERO, s),
        Color(0, 0, 0, 0.78)
    )

    draw_text_center(
        title,
        s.y * 0.40,
        48,
        Color("#00dfff")
    )

    draw_text_center(
        subtitle,
        s.y * 0.48,
        20,
        Color.WHITE
    )
