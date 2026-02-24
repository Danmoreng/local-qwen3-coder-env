// 3D Snake Game - WebGL Implementation
// Uses WebGL 1.0 with custom shaders

// ============================================================================
// SHADER SOURCES
// ============================================================================

const VERTEX_SHADER_SRC = `
    attribute vec3 a_position;
    attribute vec3 a_color;
    
    uniform mat4 u_modelMatrix;
    uniform mat4 u_viewMatrix;
    uniform mat4 u_projectionMatrix;
    
    varying vec3 v_color;
    
    void main() {
        vec4 worldPosition = u_modelMatrix * vec4(a_position, 1.0);
        vec4 viewPosition = u_viewMatrix * worldPosition;
        gl_Position = u_projectionMatrix * viewPosition;
        
        v_color = a_color;
    }
`;

const FRAGMENT_SHADER_SRC = `
    precision mediump float;
    
    varying vec3 v_color;
    
    void main() {
        gl_FragColor = vec4(v_color, 1.0);
    }
`;

// ============================================================================
// WebGL Utilities
// ============================================================================

function createShader(gl, type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        console.error('Shader compile error:', gl.getShaderInfoLog(shader));
        gl.deleteShader(shader);
        return null;
    }
    return shader;
}

function createProgram(gl, vertexShader, fragmentShader) {
    const program = gl.createProgram();
    gl.attachShader(program, vertexShader);
    gl.attachShader(program, fragmentShader);
    gl.linkProgram(program);
    
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        console.error('Program link error:', gl.getProgramInfoLog(program));
        return null;
    }
    return program;
}

function createCubeBuffers(gl) {
    // Cube vertices (12 triangles = 36 vertices for a single cube)
    // Each face is a quad made of 2 triangles
    const positions = [
        // Front face (z = 0.5)
        -0.5, -0.5,  0.5,  0.5, -0.5,  0.5,  0.5,  0.5,  0.5,
        -0.5, -0.5,  0.5,  0.5,  0.5,  0.5, -0.5,  0.5,  0.5,
        // Back face (z = -0.5)
        -0.5, -0.5, -0.5, -0.5,  0.5, -0.5,  0.5,  0.5, -0.5,
        -0.5, -0.5, -0.5,  0.5,  0.5, -0.5,  0.5, -0.5, -0.5,
        // Top face (y = 0.5)
        -0.5,  0.5, -0.5, -0.5,  0.5,  0.5,  0.5,  0.5,  0.5,
        -0.5,  0.5, -0.5,  0.5,  0.5,  0.5,  0.5,  0.5, -0.5,
        // Bottom face (y = -0.5)
        -0.5, -0.5, -0.5,  0.5, -0.5, -0.5,  0.5, -0.5,  0.5,
        -0.5, -0.5, -0.5,  0.5, -0.5,  0.5, -0.5, -0.5,  0.5,
        // Right face (x = 0.5)
         0.5, -0.5, -0.5,  0.5,  0.5, -0.5,  0.5,  0.5,  0.5,
         0.5, -0.5, -0.5,  0.5,  0.5,  0.5,  0.5, -0.5,  0.5,
        // Left face (x = -0.5)
        -0.5, -0.5, -0.5, -0.5, -0.5,  0.5, -0.5,  0.5,  0.5,
        -0.5, -0.5, -0.0, -0.5,  0.5,  0.5, -0.5,  0.5, -0.5,
    ];

    // Colors for each vertex (same color for all vertices of a cube)
    // 6 components per face vertex (3 pos + 3 color)
    const colors = [];
    for (let i = 0; i < positions.length / 3; i++) {
        colors.push(1.0, 1.0, 1.0); // White base - will be modulated by attribute
    }

    // Create buffers
    const positionBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(positions), gl.STATIC_DRAW);

    const colorBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, colorBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(colors), gl.STATIC_DRAW);

    return { positionBuffer, colorBuffer };
}

function createCubeVAO(gl, program, buffers) {
    // Try to use VAO extension for WebGL 1.0, otherwise create a fallback
    const ext = gl.getExtension('OES_vertex_array_object');

    const positionLoc = gl.getAttribLocation(program, 'a_position');
    const colorLoc = gl.getAttribLocation(program, 'a_color');

    if (ext) {
        const vao = ext.createVertexArrayOES();
        ext.bindVertexArrayOES(vao);

        // Position buffer
        gl.bindBuffer(gl.ARRAY_BUFFER, buffers.positionBuffer);
        gl.enableVertexAttribArray(positionLoc);
        gl.vertexAttribPointer(positionLoc, 3, gl.FLOAT, false, 0, 0);

        // Color buffer
        gl.bindBuffer(gl.ARRAY_BUFFER, buffers.colorBuffer);
        gl.enableVertexAttribArray(colorLoc);
        gl.vertexAttribPointer(colorLoc, 3, gl.FLOAT, false, 0, 0);

        ext.bindVertexArrayOES(null);

        // Wrap the VAO to provide a bind method for consistent usage
        return {
            bind: function() {
                ext.bindVertexArrayOES(this.vao);
            },
            unbind: function() {
                ext.bindVertexArrayOES(null);
            },
            vao: vao,
            ext: ext
        };
    }

    // Fallback without VAO - store buffer info for manual binding
    // Create a combined binding function
    return {
        bind: function() {
            // Position buffer
            gl.bindBuffer(gl.ARRAY_BUFFER, buffers.positionBuffer);
            gl.enableVertexAttribArray(positionLoc);
            gl.vertexAttribPointer(positionLoc, 3, gl.FLOAT, false, 0, 0);

            // Color buffer
            gl.bindBuffer(gl.ARRAY_BUFFER, buffers.colorBuffer);
            gl.enableVertexAttribArray(colorLoc);
            gl.vertexAttribPointer(colorLoc, 3, gl.FLOAT, false, 0, 0);
        },
        unbind: function() {
            gl.bindBuffer(gl.ARRAY_BUFFER, null);
        },
        positionBuffer: buffers.positionBuffer,
        colorBuffer: buffers.colorBuffer,
        positionLoc: positionLoc,
        colorLoc: colorLoc
    };
}

// ============================================================================
// Game Constants
// ============================================================================

const GRID_SIZE = 12;
const CELL_SIZE = 1.0;
const GAME_SPEED = 150; // ms per move
const BOARD_HALF_SIZE = (GRID_SIZE * CELL_SIZE) / 2;

// Colors
const COLORS = {
    SNAKE_HEAD: [0.0, 1.0, 0.5],    // Bright neon green
    SNAKE_BODY: [0.0, 0.8, 0.3],    // Darker green
    FOOD:       [1.0, 0.2, 0.2],    // Reddish
    BOARD:      [0.1, 0.1, 0.15],   // Dark blue-grey
    GRID:       [0.15, 0.15, 0.2],  // Lighter grid lines
};

// ============================================================================
// Matrix Math Utilities
// ============================================================================

function mat4Create() {
    return new Float32Array([
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    ]);
}

function mat4Multiply(a, b) {
    const out = new Float32Array(16);
    for (let i = 0; i < 4; i++) {
        const ai0 = a[i * 4];
        const ai1 = a[i * 4 + 1];
        const ai2 = a[i * 4 + 2];
        const ai3 = a[i * 4 + 3];
        out[i] = ai0 * b[0] + ai1 * b[4] + ai2 * b[8] + ai3 * b[12];
        out[i + 4] = ai0 * b[1] + ai1 * b[5] + ai2 * b[9] + ai3 * b[13];
        out[i + 8] = ai0 * b[2] + ai1 * b[6] + ai2 * b[10] + ai3 * b[14];
        out[i + 12] = ai0 * b[3] + ai1 * b[7] + ai2 * b[11] + ai3 * b[15];
    }
    return out;
}

function mat4Perspective(fovy, aspect, near, far) {
    const f = 1.0 / Math.tan(fovy / 2);
    const nf = 1 / (near - far);
    return new Float32Array([
        f / aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, (far + near) * nf, -1,
        0, 0, (2 * far * near) * nf, 0
    ]);
}

function mat4Translate(m, x, y, z) {
    const t = new Float32Array([
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        x, y, z, 1
    ]);
    return mat4Multiply(m, t);
}

function mat4RotateX(m, angle) {
    const c = Math.cos(angle);
    const s = Math.sin(angle);
    const r = new Float32Array([
        1, 0, 0, 0,
        0, c, s, 0,
        0, -s, c, 0,
        0, 0, 0, 1
    ]);
    return mat4Multiply(m, r);
}

function mat4RotateY(m, angle) {
    const c = Math.cos(angle);
    const s = Math.sin(angle);
    const r = new Float32Array([
        c, 0, -s, 0,
        0, 1, 0, 0,
        s, 0, c, 0,
        0, 0, 0, 1
    ]);
    return mat4Multiply(m, r);
}

function mat4LookAt(eye, center, up) {
    const zAxis = [
        eye[0] - center[0],
        eye[1] - center[1],
        eye[2] - center[2]
    ];
    const zLen = Math.sqrt(zAxis[0]**2 + zAxis[1]**2 + zAxis[2]**2);
    zAxis[0] /= zLen;
    zAxis[1] /= zLen;
    zAxis[2] /= zLen;
    
    const xAxis = [
        up[1] * zAxis[2] - up[2] * zAxis[1],
        up[2] * zAxis[0] - up[0] * zAxis[2],
        up[0] * zAxis[1] - up[1] * zAxis[0]
    ];
    const xLen = Math.sqrt(xAxis[0]**2 + xAxis[1]**2 + xAxis[2]**2);
    xAxis[0] /= xLen;
    xAxis[1] /= xLen;
    xAxis[2] /= xLen;
    
    const yAxis = [
        zAxis[1] * xAxis[2] - zAxis[2] * xAxis[1],
        zAxis[2] * xAxis[0] - zAxis[0] * xAxis[2],
        zAxis[0] * xAxis[1] - zAxis[1] * xAxis[0]
    ];
    const yLen = Math.sqrt(yAxis[0]**2 + yAxis[1]**2 + yAxis[2]**2);
    yAxis[0] /= yLen;
    yAxis[1] /= yLen;
    yAxis[2] /= yLen;
    
    return new Float32Array([
        xAxis[0], xAxis[1], xAxis[2], 0,
        yAxis[0], yAxis[1], yAxis[2], 0,
        zAxis[0], zAxis[1], zAxis[2], 0,
        -(xAxis[0] * eye[0] + xAxis[1] * eye[1] + xAxis[2] * eye[2]),
        -(yAxis[0] * eye[0] + yAxis[1] * eye[1] + yAxis[2] * eye[2]),
        -(zAxis[0] * eye[0] + zAxis[1] * eye[1] + zAxis[2] * eye[2]),
        1
    ]);
}

// ============================================================================
// Game State
// ============================================================================

const Game = {
    canvas: null,
    gl: null,
    program: null,
    
    // Rendering state
    vao: null,
    modelMatrix: null,
    viewMatrix: null,
    projectionMatrix: null,
    
    // Camera
    cameraAngle: Math.PI / 4,
    cameraDistance: 25,
    
    // Game state
    snake: [],
    direction: { x: 1, y: 0 },
    nextDirection: { x: 1, y: 0 },
    food: null,
    score: 0,
    isPlaying: false,
    isPaused: false,
    lastMoveTime: 0,
    
    // Animation
    snakeColor: null,
    
    init() {
        this.canvas = document.getElementById('glCanvas');
        this.gl = this.canvas.getContext('webgl', { alpha: false, antialias: true });
        
        if (!this.gl) {
            alert('WebGL not supported!');
            return;
        }
        
        // Compile shaders
        const vertexShader = createShader(this.gl, this.gl.VERTEX_SHADER, VERTEX_SHADER_SRC);
        const fragmentShader = createShader(this.gl, this.gl.FRAGMENT_SHADER, FRAGMENT_SHADER_SRC);
        this.program = createProgram(this.gl, vertexShader, fragmentShader);
        
        // Create buffers
        const buffers = createCubeBuffers(this.gl);
        this.vao = createCubeVAO(this.gl, this.program, buffers);
        
        // Setup matrices
        this.modelMatrix = mat4Create();
        this.viewMatrix = mat4Create();
        this.projectionMatrix = mat4Create();
        
        this.resize();
        window.addEventListener('resize', () => this.resize());
        
        // Input handling
        document.addEventListener('keydown', (e) => this.handleInput(e));
        
        // UI elements
        document.getElementById('start-btn').addEventListener('click', () => this.startGame());
        document.getElementById('restart-btn').addEventListener('click', () => this.startGame());
        
        // Initial render (background)
        this.setupView();
        this.renderEmpty();
    },
    
    resize() {
        const canvas = this.canvas;
        const dpr = window.devicePixelRatio || 1;
        canvas.width = 800 * dpr;
        canvas.height = 600 * dpr;
        this.gl.viewport(0, 0, canvas.width, canvas.height);
        this.setupView();
    },
    
    setupView() {
        // Perspective projection
        const aspect = this.canvas.width / this.canvas.height;
        this.projectionMatrix = mat4Perspective(Math.PI / 4, aspect, 0.1, 1000);
        
        // Camera position
        const eyeX = this.cameraDistance * Math.cos(this.cameraAngle);
        const eyeZ = this.cameraDistance * Math.sin(this.cameraAngle);
        const eye = [eyeX, 15, eyeZ];
        const center = [0, 0, 0];
        const up = [0, 1, 0];
        
        this.viewMatrix = mat4LookAt(eye, center, up);
        this.viewMatrix = mat4RotateX(this.viewMatrix, -Math.PI / 6); // Tilt down slightly
    },
    
    startGame() {
        // Reset game state
        this.snake = [
            { x: 0, y: 0 },
            { x: -1, y: 0 },
            { x: -2, y: 0 }
        ];
        this.direction = { x: 1, y: 0 };
        this.nextDirection = { x: 1, y: 0 };
        this.score = 0;
        this.updateScore();
        this.spawnFood();
        this.isPlaying = true;
        this.isPaused = false;
        
        // Hide screens
        document.getElementById('start-screen').style.display = 'none';
        document.getElementById('game-over-screen').classList.remove('visible');
        
        this.lastMoveTime = performance.now();
    },
    
    spawnFood() {
        let validPosition = false;
        let food;
        
        while (!validPosition) {
            food = {
                x: Math.floor(Math.random() * GRID_SIZE) - Math.floor(GRID_SIZE / 2),
                y: Math.floor(Math.random() * GRID_SIZE) - Math.floor(GRID_SIZE / 2)
            };
            
            // Check if food is on snake
            validPosition = !this.snake.some(segment => segment.x === food.x && segment.y === food.y);
        }
        
        this.food = food;
    },
    
    handleInput(e) {
        if (!this.isPlaying || this.isPaused) {
            if (e.key.toLowerCase() === 'p' && !this.isPlaying) {
                // Skip to game
                document.getElementById('start-screen').style.display = 'none';
                this.startGame();
            }
            return;
        }
        
        if (e.key.toLowerCase() === 'p') {
            this.togglePause();
            return;
        }
        
        switch (e.key) {
            case 'ArrowUp':
            case 'w':
            case 'W':
                if (this.direction.y !== 1) this.nextDirection = { x: 0, y: -1 };
                break;
            case 'ArrowDown':
            case 's':
            case 'S':
                if (this.direction.y !== -1) this.nextDirection = { x: 0, y: 1 };
                break;
            case 'ArrowLeft':
            case 'a':
            case 'A':
                if (this.direction.x !== 1) this.nextDirection = { x: -1, y: 0 };
                break;
            case 'ArrowRight':
            case 'd':
            case 'D':
                if (this.direction.x !== -1) this.nextDirection = { x: 1, y: 0 };
                break;
        }
    },
    
    togglePause() {
        this.isPaused = !this.isPaused;
        if (!this.isPaused) {
            this.lastMoveTime = performance.now();
        }
    },
    
    update(dt) {
        const now = performance.now();
        
        if (this.isPaused || !this.isPlaying) return;
        
        if (now - this.lastMoveTime > GAME_SPEED) {
            this.lastMoveTime = now;
            this.moveSnake();
        }
    },
    
    moveSnake() {
        this.direction = this.nextDirection;
        
        const head = this.snake[0];
        const newHead = {
            x: head.x + this.direction.x,
            y: head.y + this.direction.y
        };
        
        // Check wall collision
        const limit = Math.floor(GRID_SIZE / 2);
        if (newHead.x < -limit || newHead.x >= limit || newHead.y < -limit || newHead.y >= limit) {
            this.gameOver();
            return;
        }
        
        // Check self collision
        if (this.snake.some(segment => segment.x === newHead.x && segment.y === newHead.y)) {
            this.gameOver();
            return;
        }
        
        this.snake.unshift(newHead);
        
        // Check food collision
        if (this.food && newHead.x === this.food.x && newHead.y === this.food.y) {
            this.score += 10;
            this.updateScore();
            this.spawnFood();
            // Don't remove tail - snake grows
        } else {
            this.snake.pop();
        }
    },
    
    updateScore() {
        document.getElementById('score').textContent = `Score: ${this.score}`;
    },
    
    gameOver() {
        this.isPlaying = false;
        document.getElementById('final-score').textContent = this.score;
        document.getElementById('game-over-screen').classList.add('visible');
    },
    
    getCellWorldPos(cellX, cellY) {
        const worldSize = GRID_SIZE * CELL_SIZE;
        const offsetX = -worldSize / 2 + CELL_SIZE / 2;
        const offsetY = -worldSize / 2 + CELL_SIZE / 2;
        return {
            x: offsetX + cellX * CELL_SIZE,
            y: offsetY + cellY * CELL_SIZE
        };
    },
    
    renderCube(x, y, z, color) {
        const modelMatrix = mat4Create();
        const translated = mat4Translate(modelMatrix, x, y, z);
        const finalMatrix = mat4Multiply(mat4Multiply(this.projectionMatrix, this.viewMatrix), translated);
        
        this.gl.uniformMatrix4fv(
            this.gl.getUniformLocation(this.program, 'u_projectionMatrix'),
            false,
            this.projectionMatrix
        );
        this.gl.uniformMatrix4fv(
            this.gl.getUniformLocation(this.program, 'u_viewMatrix'),
            false,
            this.viewMatrix
        );
        this.gl.uniformMatrix4fv(
            this.gl.getUniformLocation(this.program, 'u_modelMatrix'),
            false,
            finalMatrix
        );
        
        // Set color
        this.gl.uniform3f(
            this.gl.getUniformLocation(this.program, 'a_color'),
            color[0], color[1], color[2]
        );
        
        this.vao.bind();
        this.gl.drawArrays(this.gl.TRIANGLES, 0, 36);
    },
    
    renderEmpty() {
        const gl = this.gl;
        gl.clearColor(0.09, 0.09, 0.12, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        
        this.setupView();
        
        // Render empty board grid
        this.renderBoardGrid();
        
        this.vao.unbind();
    },
    
    renderBoardGrid() {
        const gl = this.gl;
        
        const limit = Math.floor(GRID_SIZE / 2);
        const worldSize = GRID_SIZE * CELL_SIZE;
        
        // Create a simple grid using lines
        const gridPositions = [];
        for (let i = -limit; i <= limit; i++) {
            // Horizontal lines
            gridPositions.push(
                -worldSize / 2, i * CELL_SIZE, 0,
                worldSize / 2, i * CELL_SIZE, 0
            );
            // Vertical lines
            gridPositions.push(
                i * CELL_SIZE, -worldSize / 2, 0,
                i * CELL_SIZE, worldSize / 2, 0
            );
        }
        
        const gridBuffer = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, gridBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(gridPositions), gl.STATIC_DRAW);
        
        const program = this.program;
        const positionLoc = gl.getAttribLocation(program, 'a_position');
        gl.bindBuffer(gl.ARRAY_BUFFER, gridBuffer);
        gl.enableVertexAttribArray(positionLoc);
        gl.vertexAttribPointer(positionLoc, 3, gl.FLOAT, false, 0, 0);
        
        const modelMatrix = mat4Create();
        const finalMatrix = mat4Multiply(mat4Multiply(this.projectionMatrix, this.viewMatrix), modelMatrix);
        
        gl.uniformMatrix4fv(gl.getUniformLocation(program, 'u_projectionMatrix'), false, this.projectionMatrix);
        gl.uniformMatrix4fv(gl.getUniformLocation(program, 'u_viewMatrix'), false, this.viewMatrix);
        gl.uniformMatrix4fv(gl.getUniformLocation(program, 'u_modelMatrix'), false, finalMatrix);
        
        gl.uniform3f(gl.getUniformLocation(program, 'a_color'), COLORS.GRID[0], COLORS.GRID[1], COLORS.GRID[2]);
        
        gl.drawArrays(gl.LINES, 0, gridPositions.length / 3);
        
        // Also render the board base
        const boardPositions = [
            -worldSize / 2, -worldSize / 2, 0,
            worldSize / 2, -worldSize / 2, 0,
            worldSize / 2, worldSize / 2, 0,
            -worldSize / 2, -worldSize / 2, 0,
            worldSize / 2, worldSize / 2, 0,
            -worldSize / 2, worldSize / 2, 0,
        ];
        
        const boardBuffer = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, boardBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(boardPositions), gl.STATIC_DRAW);
        
        gl.bindBuffer(gl.ARRAY_BUFFER, boardBuffer);
        gl.enableVertexAttribArray(positionLoc);
        gl.vertexAttribPointer(positionLoc, 3, gl.FLOAT, false, 0, 0);
        
        gl.uniform3f(gl.getUniformLocation(program, 'a_color'), COLORS.BOARD[0], COLORS.BOARD[1], COLORS.BOARD[2]);
        
        gl.drawArrays(this.gl.TRIANGLES, 0, 6);
    },
    
    render() {
        const gl = this.gl;
        
        // Clear
        gl.clearColor(0.09, 0.09, 0.12, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LEQUAL);
        
        this.setupView();
        
        // Render grid
        this.renderBoardGrid();
        
        // Render food
        if (this.food) {
            const pos = this.getCellWorldPos(this.food.x, this.food.y);
            
            // Food pulse effect
            const pulse = 1 + Math.sin(performance.now() / 200) * 0.1;
            
            const modelMatrix = mat4Create();
            const translated = mat4Translate(mat4Translate(mat4Translate(modelMatrix, pos.x, pos.y, 0), 0, 0, 0), 0, 0, 0);
            const scaled = mat4Translate(translated, 0, 0, 0);
            
            // Animate food position slightly
            const foodY = Math.sin(performance.now() / 300) * 0.2 + 0.3;
            
            const finalMatrix = mat4Multiply(mat4Multiply(this.projectionMatrix, this.viewMatrix), mat4Translate(mat4Create(), pos.x, pos.y + foodY, 0));
            
            gl.uniformMatrix4fv(gl.getUniformLocation(this.program, 'u_projectionMatrix'), false, this.projectionMatrix);
            gl.uniformMatrix4fv(gl.getUniformLocation(this.program, 'u_viewMatrix'), false, this.viewMatrix);
            gl.uniformMatrix4fv(gl.getUniformLocation(this.program, 'u_modelMatrix'), false, finalMatrix);
            
            gl.uniform3f(gl.getUniformLocation(this.program, 'a_color'), COLORS.FOOD[0], COLORS.FOOD[1], COLORS.FOOD[2]);
            
            this.vao.bind();
            gl.drawArrays(this.gl.TRIANGLES, 0, 36);
        }
        
        // Render snake
        this.snake.forEach((segment, index) => {
            const pos = this.getCellWorldPos(segment.x, segment.y);
            
            const finalMatrix = mat4Multiply(
                mat4Multiply(this.projectionMatrix, this.viewMatrix),
                mat4Translate(mat4Create(), pos.x, pos.y, 0)
            );
            
            gl.uniformMatrix4fv(gl.getUniformLocation(this.program, 'u_projectionMatrix'), false, this.projectionMatrix);
            gl.uniformMatrix4fv(gl.getUniformLocation(this.program, 'u_viewMatrix'), false, this.viewMatrix);
            gl.uniformMatrix4fv(gl.getUniformLocation(this.program, 'u_modelMatrix'), false, finalMatrix);
            
            const color = index === 0 ? COLORS.SNAKE_HEAD : COLORS.SNAKE_BODY;
            gl.uniform3f(gl.getUniformLocation(this.program, 'a_color'), color[0], color[1], color[2]);
            
            this.vao.bind();
            gl.drawArrays(this.gl.TRIANGLES, 0, 36);
        });
        
        this.vao.unbind();
    },
    
    gameLoop() {
        this.update();
        this.render();
        requestAnimationFrame(() => this.gameLoop());
    }
};

// Start the game when DOM is ready
window.addEventListener('DOMContentLoaded', () => {
    Game.init();
    Game.gameLoop();
});