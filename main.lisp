#!/usr/bin/ol

; ----------------------------------
; зададим размеры графического окна
(define-library (lib gl config)
(export config) (import (otus lisp))
(begin
   (define config (pairs->ff `(
      ; напомню, что мы используем фиксированный шрифт размера 9*16
      (width  . ,(* 1  9 80))      ; 80 знакомест в ширину
      (height . ,(* 1 16 25))))))) ; 25 знакомест в высоту
(import (lib gl config))

; -=( main )=------------------------------------
; подключаем графические библиотеки, создаем окно
(import (lib gl2))
(gl:set-window-title "Наруто")
(import (otus ffi))
(import (lib soil))

; -=( сразу нарисуем сплеш )=---------------------------
(glOrtho 0 1 1 0 0 1)
(glEnable GL_TEXTURE_2D)
(define id ; OpenGL texture splash ID
   (SOIL_load_OGL_texture (c-string "media/konoha.jpg") SOIL_LOAD_RGBA SOIL_CREATE_NEW_ID 0))
(glBindTexture GL_TEXTURE_2D id)
(glBegin GL_QUADS)
   ; рисуем на весь экран квадратик с текстурой
   (for-each (lambda (xy)
         (glTexCoord2f (car xy) (cdr xy))
         (glVertex2f (car xy) (cdr xy)))
      '((0 . 0) (1 . 0) (1 . 1) (0 . 1)))
(glEnd)
(glDisable GL_TEXTURE_2D)
(gl:SwapBuffers (interact 'opengl ['get 'context])) ; todo: make a function
(glDeleteTextures 1 (list id)) ; и спокойно удалим сплеш текстуру

; -------------------------------------------------------
; теперь запустим текстовую консольку
(import (lib gl console))

; временное окно дебага (покажем fps):
(define fps (create-window 70 24 10 1))
(define started (time-ms)) (define time '(0))
(define frames '(0 . 0))

(set-window-writer fps (lambda (print)
   (set-car! frames (+ (car frames) 1))
   (let ((now (time-ms)))
      (if (> now (+ started (car time) 1000))
         (begin
            (set-cdr! frames (car frames))
            (set-car! frames 0)
            (set-car! time (- now started)))))
   (print GRAY (cdr frames) " fps")
))

; ----------------
; музычка...
;,load "music.lisp" ; временно отключена

;; ; остальные игровые библиотеки
;; (import (lib math))
;; (import (otus random!))
;; (import (lang sexp))
;; (import (scheme misc))
;; (import (file xml))
;; (import (scheme dynamic-bindings))
(import (lib rlutil))

; -=( level )=-----------------
;     заведует игровой картой
,load "nani/level.lisp"
,load "nani/creature.lisp"
,load "nani/ai.lisp"

;; ;;; -=( creatures )=-----------------
;; ;;;  'creatures - заведует всеми живыми(или оживленными) созданиями

; =============================
; 1. Загрузим игровой уровень
(level:load "konoha.tmx")

; временная функция работы с level-collision
(define collision-data (level:get-layer 'collision))

(define H (length collision-data))       ; высота уровня
(define W (length (car collision-data))) ; ширина уровня

; временная функция: возвращает collision data
;  по координатам x,y на карте
(define (at x y)
   (if (and (< -1 x W) (< -1 y H))
      (lref (lref collision-data y) x)))

;; ; =================================================================
;; ; -=( hero )=---------
(define hero (make-creature 'hero #empty))
; зададим позицию героя в мире
((hero 'set-location) (cons 30 33))        ; новый способ перемещения героя - выбрать какой лучше

; зададим анимации герою, в нашем случае он будет выглядеть как человек
((hero 'set-animation-profile) 'skeleton "animations/skeleton.ini")
((hero 'set-current-animation) 'stance) ; пусть он просто стоит

((hero 'set) 'state ; задать машину состояний (сразу с текущим)
   (letrec ((alive (lambda (this action) ; стоим и ничего не делаем
               (print "alive...")
               (if action (case action
                  (['go to]
                     ; если появилась цель движения - перейдем в новое состояние
                     (let*((creature this)
                           (to to)
                           (hero ((creature 'get-location)))
                           (move (A* collision-data hero to)))
                        (print "creature: " creature)
                        (print "move: " move)
                        (if move (begin
                           ; пошлем его в дорогу
                           (creature:move-with-animation creature move 'run #f)
                        ))))
                  (['hit damage]
                     ((this 'set) 'health
                        (- ((this 'get) 'health) 30))
                     (if (> ((this 'get) 'health) 0)
                        (creature:play-animation this 'hit #f)
                        (creature:play-animation this 'die 'die))) ; (return dead)
                     ; ...
                  ))
                  #false)) ; стейт герою пока не меняем
            (dead (lambda (this action)
               (print "i'm dead!")
               ; преследование
               dead)))
      ; initial state
      alive))

((hero 'set) 'health 100)

; ----------------------------------------------------------------------------
; -=( npcs )=-----------------
(fork-server 'npcs (lambda ()
   (let this ((all #null))
   (let*((envelope (wait-mail))
         (sender msg envelope))
      (if msg
         (this (cons msg all))
         (begin
            (mail sender all)
            (this all)))))))

(for-each (lambda (info)
      (define npc (make-creature (car info) #empty))

      ; машина состояний для npc
      ((npc 'set) 'state ; задать машину состояний (сразу с текущим)
         (letrec ((patrol (lambda (this action)
                     ; пока патрулирование - это стояние на месте
                     #false))

                  ; -----------------------------------------------
                  ; преследование героя:
                  (pursuit (lambda (this action)
                     (let*((creature this)
                           (to ((hero 'get-location))) ; преследуем
                           (me ((creature 'get-location)))
                           (move (A* collision-data me to)))
                        ;; (print "creature: " creature)
                        (print "move: " move)
                        (if move
                           (print "move dist: " (inexact
                              (sqrt (+
                                       (* (car move) (car move))
                                       (* (cdr move) (cdr move))
                                    )))))

                        ; todo: если расстояние меньше N - перейти в состояние "стреляю"
                        ; todo: если расстояние больше M (или герой невидим) - перейти в состояние "патрулирую"
                        ; todo: иначе идти к герою
                        (if (and
                              move
                              (> ((hero 'get) 'health) 0))
                           (let ((delta (cons
                                    (- (car to) (car me))
                                    (- (cdr to) (cdr me)))))
                              (print "delta: " delta)
                              (cond
                                 ((equal? delta '(0 . -1))
                                    ((creature 'set-orientation) 0)
                                    (creature:play-animation creature 'shoot #f)
                                    (((hero 'get) 'state) hero ['hit 30]))
                                 ((equal? delta '(+1 . 0))
                                    ((creature 'set-orientation) 2)
                                    (creature:play-animation creature 'shoot #f)
                                    (((hero 'get) 'state) hero ['hit 30]))
                                 ((equal? delta '(0 . +1))
                                    ((creature 'set-orientation) 4)
                                    (creature:play-animation creature 'shoot #f)
                                    (((hero 'get) 'state) hero ['hit 30]))
                                 ((equal? delta '(-1 . 0))
                                    ((creature 'set-orientation) 6)
                                    (creature:play-animation creature 'shoot #f)
                                    (((hero 'get) 'state) hero ['hit 30]))
                                 (else
                                    (creature:move-with-animation creature move 'run #f)))))
                     #false)))
; ...
                  (fight (lambda (this action)
                     ; попытка ударить игрока
                     #false)))
            ; initial state
            pursuit))

      ((npc 'set-location) (cons (ref (cdr info) 3) (ref (cdr info) 4)))
      ((npc 'set-animation-profile) (string->symbol (ref (cdr info) 2)) (fold string-append "animations/" (list (ref (cdr info) 2) ".ini")))
      ((npc 'set-current-animation) 'stance)

      (mail 'npcs npc))
   (ff->list (level:get 'npcs)))

;; ; --------------------------------------------------------------------
;; ; окно, через которое мы смотрим на мир

;              x-left         y-left    x-right          y-right
;(define window (vector (+ -32 -800) -32 (+ 3645 32 -800) (+ 2048 32)))
(define window (vector -1920 -64 1920 (- 2160 64)))
(define (resize scale) ; изменение масштаба
   (let*((x (floor (/ (+ (ref window 3) (ref window 1)) 2)))
         (w (floor (* (- (ref window 3) (ref window 1)) (/ scale 2))))
         (y (floor (/ (+ (ref window 4) (ref window 2)) 2)))
         (h (floor (* (- (ref window 4) (ref window 2)) (/ scale 2)))))
      (set-ref! window 1 (- x w))
      (set-ref! window 2 (- y h))
      (set-ref! window 3 (+ x w))
      (set-ref! window 4 (+ y h))))
(define (move dx dy) ; сдвинуть окно
   (let*((x (floor (* (- (ref window 3) (ref window 1)) 0.01)))
         (y (floor (* (- (ref window 4) (ref window 2)) 0.01))))
      (set-ref! window 1 (+ (ref window 1) (* dx x)))
      (set-ref! window 2 (- (ref window 2) (* dy y)))
      (set-ref! window 3 (+ (ref window 3) (* dx x)))
      (set-ref! window 4 (- (ref window 4) (* dy y)))))

; функция перевода экранных координат в номер тайла, на который они попадают
(define (xy:screen->tile xy)
   (let ((x1 (ref window 1)) (x2 (ref window 3))
         (y1 (ref window 2)) (y2 (ref window 4)))
   (let ((x2-x1 (- x2 x1)) (y2-y1 (- y2 y1))
         (w (ref gl:window-dimensions 3)) (h (ref gl:window-dimensions 4)))
   (let ((X (floor (+ x1 (/ (* (car xy) x2-x1) w))))
         (Y (floor (+ y1 (/ (* (cdr xy) y2-y1) h)))))
   (let ((w (level:get 'tilewidth))
         (h (level:get 'tileheight)))
   (let ((x (+ (/ X w) (/ Y h)))
         (y (- (/ Y h) (/ X w))))
      (cons (floor x) (floor y))))))))

;; ;(resize 1/3) ; временно: увеличим карту в 3 раза

; init
(glShadeModel GL_SMOOTH)
(glBlendFunc GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA)
(gl:hide-cursor)

;; ; служебные переменные
;; (define timestamp (box 0))
(define calculating-world (box 0))
(define (world-busy?)
   (less? 0 (unbox calculating-world)))

; draw
(gl:set-renderer (lambda (mouse)
   ; тут мы поворачиваем нашего героя в сторону мышки
   (unless (world-busy?) (if (> ((hero 'get) 'health) 0)
      (let*((mousetile (xy:screen->tile mouse))
            (herotile ((hero 'get-location)))
            (dx (- (car mousetile) (car herotile)))
            (dy (- (cdr mousetile) (cdr herotile))))
         (cond
            ((and (= dx 0) (< dy 0))
               ((hero 'set-orientation) 0))
            ((and (= dx 0) (> dy 0))
               ((hero 'set-orientation) 4))
            ((and (< dx 0) (= dy 0))
               ((hero 'set-orientation) 6))
            ((and (> dx 0) (= dy 0))
               ((hero 'set-orientation) 2))

            ((and (= dx +1) (= dy +1))
               ((hero 'set-orientation) 3))
            ((and (= dx -1) (= dy +1))
               ((hero 'set-orientation) 5))
            ((and (= dx -1) (= dy -1))
               ((hero 'set-orientation) 7))
            ((and (= dx +1) (= dy -1))
               ((hero 'set-orientation) 1))
         ))))

;;    ; просто регулярные действия
;;    (let*((ss ms (clock))
;;          (i (mod (floor (/ (+ (* ss 1000) ms) (/ 1000 4))) 4)))

;;       (unless (eq? i (unbox timestamp))
;;          (begin
;;             (set-car! timestamp i)

;;             ; надо послать нипам 'tick, а вдруг они захотят с ноги на ногу попереминаться...

;;             ;; ; события нипов пускай остаются асинхронными,
;;             ;; ; просто перед рисованием убедимся что они все закончили свою работу
;;             ;; (for-each (lambda (id)
;;             ;;       (mail id ['process-event-transition-tick]))
;;             ;;    (interact 'creatures ['get 'skeletons]))
;;          )))

   ; теперь можем и порисовать: очистим окно и подготовим оконную математику
   (glClearColor 0.0 0.0 0.0 1)
   (glClear GL_COLOR_BUFFER_BIT)
   (glLoadIdentity)
   (glOrtho (ref window 1) (ref window 3) (ref window 4) (ref window 2) -1 1) ; invert axis Y on screen!
   (glEnable GL_TEXTURE_2D)
   (glEnable GL_BLEND)

   ; теперь попросим уровень отрисовать себя
   (define creatures (append
      (map (lambda (npc)
            [ ((npc 'get-location))
              ((npc 'get-animation-frame))])
         (interact 'npcs #false))
      (list
         [ (interact 'hero (list 'get-location))
           (interact 'hero (list 'get-animation-frame))])
   ))

   (level:draw #|(if mouse (xy:screen->tile mouse))|# creatures)

   ; окошки, консолька, etc.
   (render-windows)

   ; let's draw mouse pointer
   (if mouse
      (let*(;(ms (mod (floor (/ (time-ms) 100)) 40))
            (tile (getf (level:get 'tileset)
                        (+ (level:get-gid 'pointer)
                           (if (world-busy?) 1 0))))
;;                            ;; (cond
;;                            ;;    ((world-busy?) 1)
;;                            ;;    ((let ((xy (xy:screen->tile mouse)))
;;                            ;;       (and (< (car xy) (level:get 'width))
;;                            ;;            (< (cdr xy) (level:get 'height))
;;                            ;;            (>= (car xy) 0)
;;                            ;;            (>= (cdr xy) 0)
;;                            ;;            (A* collision-data xy (creature:get-location 'hero))))
;;                            ;;       0)
;;                            ;;    (else 3)))))
;;                         ;; (unless (unbox calculating-world)
;;                         ;;    (+ 1212 ms)
;;                         ;;    (+ 1292 ms))))
            (w (/ (- (ref window 3) (ref window 1)) 48)) ;  размер курсора
            (st (ref tile 5))
            ; window mouse to opengl mouse:
            (x (+ (ref window 1) (* (car mouse) (- (ref window 3) (ref window 1)) (/ 1 (ref gl:window-dimensions 3)))))
            (y (+ (ref window 2) (* (cdr mouse) (- (ref window 4) (ref window 2)) (/ 1 (ref gl:window-dimensions 4))))))
         (glEnable GL_TEXTURE_2D)
         (glEnable GL_BLEND)
         (glBindTexture GL_TEXTURE_2D (ref tile 1))
         (glBegin GL_QUADS)
            (glTexCoord2f (ref st 1) (ref st 2))
            (glVertex2f x y)

            (glTexCoord2f (ref st 3) (ref st 2))
            (glVertex2f (+ x w) y)

            (glTexCoord2f (ref st 3) (ref st 4))
            (glVertex2f (+ x w) (+ y w))

            (glTexCoord2f (ref st 1) (ref st 4))
            (glVertex2f x (+ y w))
         (glEnd)))


;;    ; coordinates
;;    #|
;;    (glDisable GL_TEXTURE_2D)
;;    (glEnable GL_LINE_STIPPLE)
;;    (glLineWidth 2.0)
;;    (glLineStipple 2 #xAAAA)
;;    (glBegin GL_LINES)
;;       (glColor3f 1 0 0)
;;       (glVertex2f -4096 0)
;;       (glVertex2f +4096 0)
;;       ;; (glColor3f 1 0 1)
;;       ;; (glVertex2f -4096 1024)
;;       ;; (glVertex2f +4096 1024)
;;       (glColor3f 0 1 0)
;;       (glVertex2f 0 -4096)
;;       (glVertex2f 0 +4096)
;;       ;; (glColor3f 0 1 1)
;;       ;; (glVertex2f 1024 -4096)
;;       ;; (glVertex2f 1024 +4096)
;;    (glEnd)
;;    (glDisable GL_LINE_STIPPLE)
;;    ;|#




   ; -------------
   ; обработчик состояния клавиатуры
   ;  внимание, это "состояние", а не "события"!
   ;  посему можно обрабатывать сразу несколько нажатий клавиатуры одновременно
   (if (key-pressed #x3d) (resize 0.9)) ;=
   (if (key-pressed #x2d) (resize 1.1)) ;-
   (if (key-pressed #xff53) (move +1 0)); right
   (if (key-pressed #xff51) (move -1 0)); left
   (if (key-pressed #xff52) (move 0 +1)); up
   (if (key-pressed #xff54) (move 0 -1)); down

   #null))


;; ; --------------------------------------------
;; ;; (define (unX x y tw th)
;; ;;    (+ (- (* x (/ w 2))
;; ;;          (* y (/ w 2)))
;; ;;       (- (/ (* width w) 4) (/ w 2))))

;; ;; (define (unY x y tw th)
;; ;;    (+ (+ (* x (/ h 2))
;; ;;          (* y (/ h 2)))
;; ;;       (- h th)))
;; ; --------------------------------------------


;; ; keyboard
;; ; обработчик событий клавиатуры
;; ;  внимание, это "события", а не "состояние"!!!
;; (gl:set-keyboard-handler (lambda (key)
;;    (print "key: " key)
;;    (case key
;;       (#x18
;;          ;(mail 'music ['shutdown])
;;          (halt 1))))) ; q - quit

(gl:set-mouse-handler (lambda (button x y)
   (print "mouse: " button " (" x ", " y ")")
   (unless (world-busy?) ; если мир сейчас не просчитывается (todo: оформить отдельной функцией)
      (cond
         ((and (eq? button 1) (> ((hero 'get) 'health) 0))
            (set-car! calculating-world (+ (unbox calculating-world) 1))
            (let ((tile (xy:screen->tile (cons x y))))
               (mail 'game ['go tile])))
         ;; ((eq? button 3) ; ПКМ
         ;;    (set-car! calculating-world (+ (unbox calculating-world) 1))
         ;;    (mail 'game ['turn]))
         (else
            ; nothing
            #true))
   )))

(fork-server 'game (lambda ()
   (let this ((itself #empty))
   (let*((envelope (wait-mail))
         (sender msg envelope))
      (case msg
;;          (['turn]
;;             (let ((creatures
;;                      (sort (lambda (a b)
;;                               (less? (car a) (car b)))
;;                         (ff->list (interact 'creatures ['debug])))))
;; ;;             ; 1. Каждому надо выдать некотрое количество action-points (сколько действий он может выполнить за ход)
;; ;;             ;  это, конечно же, зависит от npc - у каждого может быть разное
;; ;;             ; TBD.

;; ;;             ; 2. Отсортировать всех по уровню инициативности, то есть кто имеет право ударить первым
;; ;;             ;  это тоже зависит от npc

;; ;;             ; 3. И только теперь подергать каждого - пусть походит
;; ;;             ;  причем следующего можно дергать только после того, как отработают все запланированные анимации хода
;;             (for-each (lambda (creature)
;;                   (let*((creature (cdr creature))
;;                         (state ((creature 'get) 'state))
;;                         (_ (print "state: " state))
;;                         (state (if state (state creature #false))))
;;                      (if state
;;                         ((creature 'set) 'state state))))
;; ;;                   ; для тестов - пусть каждый скелет получает урон "-50"
;; ;;                   (ai:make-action creature 'damage 50))
;;                creatures)

;;             ; вроде все обработали, можно переходить в состояние "готов к следующему ходу"
;;             (set-car! calculating-world (- (unbox calculating-world) 1))
;;             (this itself)))
;; ;;          ((fire-in-the-tile xy)
;; ;;             (for-each (lambda (creature)
;; ;;                   ; для тестов - пусть каждый скелет получает урон "-50"
;; ;;                   (if (equal? (interact creature ['get 'location]) xy)
;; ;;                      (ai:make-action creature 'damage 50)))
;; ;;                (interact 'creatures ['get 'skeletons]))
;; ;;             (set-car! calculating-world #false)
;; ;;             (this itself))

         (['go to]
            (print "go to " to)
            (let*((creature (interact 'creatures ['get 'hero]))
                  (state ((creature 'get) 'state))
                  (state (if state (state creature ['go to]))))
               (if state
                  ((creature 'set) 'state state)))

            ; а теперь пускай ходят npc
            (let ((creatures
                     (sort (lambda (a b)
                              (less? a b)) ; todo: отсортировать по инициативности
                        (interact 'npcs #false))))
               (for-each (lambda (creature)
                     (print "NPC: " creature)
                     (let*((creature creature)
                           (state ((creature 'get) 'state))
                           ;; (_ (print "NPC state: " state))
                           (state (if state (state creature #false))))
                        (if state
                           ((creature 'set) 'state state))))
                  creatures))

            (set-car! calculating-world (- (unbox calculating-world) 1))
            (this itself))
         (else
            (print "logic: unhandled event: " msg)
            (this itself)))))))
