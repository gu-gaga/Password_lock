module password_lock(
    input clk,               // 100MHz 时钟
    input rstn,              // 低电平复位
    input [9:0] sw,          // 拨码开关，输入数字(0-9)
    input input_btn,         // 输入密码键
    input confirm_btn,       // 确认键
    input back_btn,          // 退格键
    input admin_btn,         // 管理员键
    input change_btn,        // 切换密码键
    output reg [15:0] led,   // LED 指示
    output reg [7:0] seg,    // 数码管段选
    output reg [7:0] an      // 数码管位选
);

    // =======================
    // 参数定义
    // =======================
    localparam WAIT     = 4'd0;
    localparam INPUT    = 4'd1;
    localparam UNLOCK   = 4'd2;
    localparam ALARM    = 4'd3;
    localparam SET_PWD  = 4'd4;
    localparam ERROR    = 4'd5;    // 错误显示状态
    localparam FINAL_ERROR = 4'd6; // 最终错误状态（第三次错误）
    localparam SIM_PWD = 4'd7;     // 密码过简状态

    // 工具变量
    integer i, k;
    reg match_var;                 // 密码匹配结果，1表示匹配，0表示不匹配
    reg [3:0] state, next_state;

    // 密码存储
    reg [3:0] password [0:5];      // 存储6位密码，每位4比特
    reg [3:0] input_buf [0:5];     // 用户输入缓冲区，存储输入的密码
    reg [3:0] temp_password [0:5]; // 管理员设置密码时的临时存储
    reg [2:0] idx;                 // 输入指针，表示当前输入到第几位（0-5）
    reg [1:0] fail_count;          // 错误计数，记录密码错误次数（0-3）
    reg unlocked;                  // 开锁标志，1表示锁已打开
    reg alarm;                     // 报警标志，1表示需要报警
    reg [3:0] current_digit;       // 当前选择的数字
    reg digit_valid;               // 数字有效信号

    // 定时器 - 32位足够计时约43秒（100MHz时钟）
    reg [31:0] idle_timer;         // 无操作计时器，用于超时返回
    reg [31:0] unlock_timer;       // 开锁状态计时器
    reg [31:0] error_timer;        // 错误显示计时器/密码过简计时器
    reg [31:0] final_error_timer;  // 最终错误计时器
    reg blink_flag;                // 闪烁标志

    // 动态扫描
    reg [19:0] scan_counter;       // 扫描计数器，用于数码管动态扫描
    reg [2:0] scan_sel;            // 当前扫描的数码管索引（0-5）
    
    // 显示切换：0-数字 1-点
    reg hide_num;
    
    // 开锁状态倒计时
    reg [7:0] countdown_seconds;  // 倒计时秒数
    reg [7:0] countdown_tens;     // 倒计时十位数
    reg [7:0] countdown_ones;     // 倒计时个位数

    // 按键同步与边沿检测
    reg input_s0, input_s1;        //输入密码键的两级同步寄存器
    reg confirm_s0, confirm_s1;    // 确认键的两级同步寄存器
    reg back_s0, back_s1;          // 退格键的两级同步寄存器  
    reg admin_s0, admin_s1;        // 管理员键的两级同步寄存器
    reg change_s0, change_s1;      // 切换密码键的两级同步寄存器
    reg input_edge, confirm_edge, back_edge, admin_edge,change_edge; // 按键上升沿信号
    reg [9:0] sw_prev;             // 上一次的sw值，用于检测变化

    // =======================
    // 初始化缺省密码 "123456"
    // =======================
    initial begin
        password[0]=4'd1; password[1]=4'd2; password[2]=4'd3;
        password[3]=4'd4; password[4]=4'd5; password[5]=4'd6;
        for (i = 0; i < 6; i = i + 1) begin
            temp_password[i] <= 4'hF;
        end
    end

    // 开锁状态倒计时30s
    always @(*) begin
        countdown_seconds = 8'd0;
        countdown_tens = 8'd0;
        countdown_ones = 8'd0;
        
        if (state == INPUT) begin
            // 15秒倒计时计算
            countdown_seconds = 15 - (idle_timer / 100_000_000);
            countdown_tens = countdown_seconds / 10;
            countdown_ones = countdown_seconds % 10;
        end
        else if (state == UNLOCK) begin
            // 30秒倒计时计算
            countdown_seconds = 30 - (unlock_timer / 100_000_000);
            countdown_tens = countdown_seconds / 10;
            countdown_ones = countdown_seconds % 10;
        end
        else if (state == ERROR || state == SIM_PWD) begin
            // 3秒倒计时计算
            countdown_seconds = 3 - (error_timer / 100_000_000);
            countdown_tens = countdown_seconds / 10;
            countdown_ones = countdown_ones;
        end
    end

    // =======================
    // 同步按键并产生单周期上升沿脉冲
    // =======================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            input_s0 <= 0; input_s1 <= 0; input_edge <= 0;
            confirm_s0 <= 0; confirm_s1 <= 0; confirm_edge <= 0;
            back_s0 <= 0; back_s1 <= 0; back_edge <= 0;
            admin_s0 <= 0; admin_s1 <= 0; admin_edge <= 0;
            change_s0 <= 0; change_s1 <= 0; change_edge <= 0;
        end else begin
            // 同步
            input_s0 <= input_btn;
            input_s1 <= input_s0;
            confirm_s0 <= confirm_btn;
            confirm_s1 <= confirm_s0;
            back_s0 <= back_btn;
            back_s1 <= back_s0;
            admin_s0 <= admin_btn;
            admin_s1 <= admin_s0;
            change_s0 <= change_btn;
            change_s1 <= change_s0;

            // 上升沿检测
            input_edge <= (input_s0 & ~input_s1);
            confirm_edge <= (confirm_s0 & ~confirm_s1);
            back_edge    <= (back_s0 & ~back_s1);
            admin_edge   <= (admin_s0 & ~admin_s1);
            change_edge   <= (change_s0 & ~change_s1);
        end
    end

    // 切换显示模式
    // =======================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            hide_num <= 0;
        end else if (change_edge) begin
            hide_num <= ~hide_num;
        end
    end

    // =======================
    // 计算匹配条件
    // =======================
    always @(*) begin
        match_var = 1'b1;
        for (k = 0; k < 6; k = k + 1) begin
            if (input_buf[k] != password[k]) begin
                match_var = 1'b0;
            end
        end
    end

    // =======================
    // 单开关数字编码器
    // =======================
    always @(*) begin
        digit_valid = 1'b0;
        current_digit = 4'hF;
        
        // 检测哪个开关打开，直接对应数字0-9
        case (sw)
            10'b0000000001: begin current_digit = 4'd0; digit_valid = 1'b1; end
            10'b0000000010: begin current_digit = 4'd1; digit_valid = 1'b1; end
            10'b0000000100: begin current_digit = 4'd2; digit_valid = 1'b1; end
            10'b0000001000: begin current_digit = 4'd3; digit_valid = 1'b1; end
            10'b0000010000: begin current_digit = 4'd4; digit_valid = 1'b1; end
            10'b0000100000: begin current_digit = 4'd5; digit_valid = 1'b1; end
            10'b0001000000: begin current_digit = 4'd6; digit_valid = 1'b1; end
            10'b0010000000: begin current_digit = 4'd7; digit_valid = 1'b1; end
            10'b0100000000: begin current_digit = 4'd8; digit_valid = 1'b1; end
            10'b1000000000: begin current_digit = 4'd9; digit_valid = 1'b1; end
            default: begin current_digit = 4'hF; digit_valid = 1'b0; end
        endcase
    end

    // =======================
    // 状态转移逻辑
    // =======================
    always @(*) begin
        next_state = state;

        case (state)
            WAIT: begin
                if (input_edge) begin
                    next_state = INPUT;
                end
                else if (admin_edge && sw == 10'b0000001111) begin
                    next_state = SET_PWD;
                end
            end

            INPUT: begin
                if (confirm_edge && idx == 6) begin
                    // 已有6位，进行验证
                    if (match_var) begin
                        next_state = UNLOCK;
                    end else begin
                        if (fail_count == 2) begin
                            next_state = FINAL_ERROR; // 第三次错误
                        end else begin
                            next_state = ERROR; // 第一或第二次错误
                        end
                    end
                end else if (admin_edge && sw == 10'b0000001111) begin
                    next_state = SET_PWD;
                end
                
                // INPUT状态15秒无操作返回等待状态
                if (idle_timer >= 15*100_000_000) begin
                    next_state = WAIT;
                end
            end

            UNLOCK: begin
                if (unlock_timer >= 30*100_000_000) begin
                    next_state = WAIT;
                end else if (admin_edge && sw == 10'b0000001111) begin
                    next_state = SET_PWD;
                end else if (confirm_edge) begin // 用户按下确定键回到等待状态
                    next_state = WAIT;
                end
            end

            ALARM: begin
                if (admin_edge && sw == 4'b1111) begin
                    next_state = WAIT;
                end
            end

            SET_PWD: begin
                if (confirm_edge && idx == 6) begin
                    if (temp_password[0] == temp_password[1] &&
                    temp_password[0] == temp_password[2] &&
                    temp_password[0] == temp_password[3] &&
                    temp_password[0] == temp_password[4] &&
                    temp_password[0] == temp_password[5]) begin
                        next_state = SIM_PWD;
                    end else begin 
                        next_state = WAIT;
                    end
                end else if (admin_edge && sw == 10'b0000001111) begin
                    next_state = WAIT; // 管理员按键退出
                end
            end
            
            ERROR: begin
                if (error_timer >= 3*100_000_000) begin
                    next_state = INPUT; // 3秒后回到输入状态
                end
            end
            
            FINAL_ERROR: begin
                // 第三次错误后一直闪烁，直到管理员处理
                if (admin_edge && sw == 10'b0000001111) next_state = WAIT;
            end

            SIM_PWD: begin
                //密码过简后led4亮3s，回到设置密码状态
                if (error_timer >= 3*100_000_000) begin
                    next_state = SET_PWD; 
                end 
            end
            
            default: next_state = WAIT;
        endcase
    end

    // =======================
    // 计时器与状态寄存
    // =======================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= WAIT;
            idx <= 0;
            fail_count <= 0;
            unlocked <= 0;
            alarm <= 0;
            idle_timer <= 0;
            unlock_timer <= 0;
            error_timer <= 0;
            final_error_timer <= 0;
            blink_flag <= 0;
            sw_prev <= 10'b0000000000;
            // 复位时重新设置为初始密码 "123456"
            password[0] <= 4'd1; password[1] <= 4'd2; password[2] <= 4'd3;
            password[3] <= 4'd4; password[4] <= 4'd5; password[5] <= 4'd6;
            // 初始化输入缓冲区
            for (i = 0; i < 6; i = i + 1) begin
                input_buf[i] <= 4'hF;
                temp_password[i] <= 4'hF;
            end
        end else begin
            state <= next_state;

            // 更新 idle_timer - 只在INPUT状态检测无操作
            if (state == INPUT) begin
                if (input_edge || confirm_edge || back_edge || admin_edge || (sw != sw_prev)) begin
                    idle_timer <= 0;
                end else
                    idle_timer <= idle_timer + 1;
            end else begin
                idle_timer <= 0;
            end

            // unlock_timer 仅在 UNLOCK 状态增加
            if (state == UNLOCK) begin
                unlock_timer <= unlock_timer + 1;
            end else
                unlock_timer <= 0;

            // error_timer 在 ERROR 状态增加
            if (state == ERROR || state == SIM_PWD) begin
                error_timer <= error_timer + 1;
            end else
                error_timer <= 0;

            // final_error_timer 在 FINAL_ERROR 状态增加
            if (state == FINAL_ERROR) begin
                final_error_timer <= final_error_timer + 1;
                
                // 闪烁控制（0.5秒周期）- 在FINAL_ERROR状态下持续闪烁
                if (final_error_timer % 50_000_000 == 0) begin
                    blink_flag <= ~blink_flag;
                    
                end
                
            end else begin
                final_error_timer <= 0;
                blink_flag <= 0;
            end

            sw_prev <= sw;

            // 处理状态转换时的特殊逻辑
            case (next_state)
                WAIT: begin
                    if (state == SET_PWD && confirm_edge) begin
                        // 完成密码设置 - 立即更新密码
                        for (i = 0; i < 6; i = i + 1) begin
                            password[i] <= temp_password[i];
                        end
                    end
                    if (state != WAIT) begin
                        // 进入等待状态时重置所有变量
                        idx <= 0;
                        fail_count <= 0;
                        unlocked <= 0;
                        alarm <= 0;
                        for (i = 0; i < 6; i = i + 1) begin
                            input_buf[i] <= 4'hF;
                            temp_password[i] <= 4'hF;
                        end
                    end
                end
                
                INPUT: begin
                    if (state == ERROR) begin
                        // 从ERROR状态回到INPUT时清空所有输入
                        idx <= 0;
                        for (i = 0; i < 6; i = i + 1) input_buf[i] <= 4'hF;
                    end
                    
                    // 确认键处理
                    if (confirm_edge && state == INPUT && digit_valid) begin
                        if (idx < 6) begin
                            // 固定当前位并移动到下一位
                            input_buf[idx] <= current_digit;
                            idx <= idx + 1;
                        end
                    end
                    
                    // 退格键处理
                    if (back_edge && state == INPUT && idx > 0) begin
                        idx <= idx - 1;
                        input_buf[idx] <= 4'hF;
                    end
                end
                
                UNLOCK: begin
                    // 解锁状态处理
                    unlocked <= 1;
                    fail_count <= 0;
                end
                
                ALARM: begin
                    alarm <= 1;
                end
                
                SET_PWD: begin
                    // 进入设置密码状态时重置索引
                    if (state != SET_PWD) begin
                        idx <= 0;
                        for (i = 0; i < 6; i = i + 1) begin
                            temp_password[i] <= 4'hF;
                        end
                    end
                    
                    // 管理员设置密码
                    if (confirm_edge && idx < 6 && digit_valid) begin
                        temp_password[idx] <= current_digit;
                        idx <= idx + 1;
                    end

                        // 退格键处理
                    if (back_edge && idx > 0) begin
                        idx <= idx - 1;
                        temp_password[idx] <= 4'hF;
                    end
                    
                end
                
                ERROR: begin
                    // 进入ERROR状态时增加错误计数
                    if (state == INPUT) begin
                        fail_count <= fail_count + 1;
                    end
                end
                
                FINAL_ERROR: begin
                    // 进入FINAL_ERROR状态时设置错误计数和报警
                    if (state == INPUT) begin
                        alarm <= 1;
                    end
                end
            endcase
        end
    end

    // =======================
    // 数码管动态扫描显示
    // =======================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            scan_counter <= 0;
            scan_sel <= 0;
        end else begin
            scan_counter <= scan_counter + 1;
            if (scan_counter[12:0] == 0) begin      // 每8192个时钟周期触发一次
                if (scan_sel == 7) begin
                    scan_sel <= 0;
                end else begin
                    scan_sel <= scan_sel + 1;
                end
            end
        end
    end

    always @(*) begin
        an  = 8'b11111111;
        seg = 8'b11111111;

        // 选择要显示的数码管
        if (scan_sel < 6) begin
            an[5 - scan_sel] = 0;
        end else if (scan_sel == 6|7) begin
            an[scan_sel] = 0;
        end

        case (state)
            ERROR: begin
                // 显示 "Error"：AN5=E, AN4=r, AN3=r, AN2=o, AN1=r
                case (scan_sel)
                    0: seg = 8'b10000110; // E
                    1: seg = 8'b10101111; // r
                    2: seg = 8'b10101111; // r
                    3: seg = 8'b10100011; // o
                    4: seg = 8'b10101111; // r
                    default: seg = 8'b11111111;
                endcase
            end
            
            FINAL_ERROR: begin
                // 立即开始闪烁显示8个H，亮1s灭0.5s
                if (blink_flag) begin
                    // 亮：显示H
                    seg = 8'b10001001; // H
                end else begin
                    // 灭
                    seg = 8'b11111111;
                end
                // 所有数码管都显示相同内容
                an = 8'b00000000;
            end
            
            SET_PWD: begin
                // 管理员设置密码时实时显示，和用户输入一样
                if (scan_sel < idx && idx <=5) begin
                    if (hide_num) begin
                        // 隐藏数字显示点
                        seg = seg_decode(4'hE);
                    end else begin
                        // 显示已固定的数字
                        seg = seg_decode(temp_password[scan_sel]);
                    end
                end else if (scan_sel == idx && state == INPUT && idx <= 5) begin
                    if (hide_num) begin
                        // 隐藏数字显示点
                        seg = seg_decode(4'hE);
                    end else begin
                        // 显示当前输入的数字
                        seg = seg_decode(current_digit);
                    end
                end else begin
                    // 显示横杠
                    seg = seg_decode(4'hF);
                end
            end
            
            UNLOCK: begin
                // 正常显示输入内容，最右边两个数码管显示倒计时
                if (scan_sel == 7) begin
                    // 第5个数码管显示倒计时十位数
                    seg = seg_decode(countdown_tens);
                end else if (scan_sel == 6) begin
                    // 第6个数码管显示倒计时个位数
                    seg = seg_decode(countdown_ones);
                end
            end
            
            default: begin
                // 正常显示输入内容，最右边两个数码管显示倒计时
                if (scan_sel < idx && idx <= 5) begin 
                    if (hide_num) begin
                        // 隐藏数字显示点
                        seg = seg_decode(4'hE);
                    end else begin
                        // 显示已固定的数字
                        seg = seg_decode(input_buf[scan_sel]);
                    end
                end else if (scan_sel == idx && state == INPUT && idx <= 5) begin
                    if (hide_num) begin
                        // 隐藏数字显示点
                        seg = seg_decode(4'hE);
                    end else begin
                        // 显示当前输入的数字
                        seg = seg_decode(current_digit);
                    end
                end else if (scan_sel == 7) begin
                    // 第5个数码管显示倒计时十位数
                    seg = seg_decode(countdown_tens);
                end else if (scan_sel == 6) begin
                    // 第6个数码管显示倒计时个位数
                    seg = seg_decode(countdown_ones);
                end else begin
                    // 显示横杠
                    seg = seg_decode(4'hF);
                end
            end
            
        endcase
    end

    // 数码管段码解码函数
    function [7:0] seg_decode(input [3:0] num);
        case(num)
            4'h0: seg_decode = 8'b11000000; // 0
            4'h1: seg_decode = 8'b11111001; // 1
            4'h2: seg_decode = 8'b10100100; // 2
            4'h3: seg_decode = 8'b10110000; // 3
            4'h4: seg_decode = 8'b10011001; // 4
            4'h5: seg_decode = 8'b10010010; // 5
            4'h6: seg_decode = 8'b10000010; // 6
            4'h7: seg_decode = 8'b11111000; // 7
            4'h8: seg_decode = 8'b10000000; // 8
            4'h9: seg_decode = 8'b10010000; // 9
            4'hE: seg_decode = 8'b01111111; // "."
            4'hF: seg_decode = 8'b10111111; // "-"
            default: seg_decode = 8'b11111111; // 全灭
        endcase
    endfunction

    // =======================
    // LED 指示
    // =======================
    always @(*) begin
        led = 16'h0000;
        // 开锁状态亮led0
        if (state == UNLOCK) begin
            led[0] = 1;
        end
        // 警报状态亮led15
        if (state == ALARM || state == FINAL_ERROR) begin
            led[15] = 1;
        end
        // 管理员状态亮led2
        if (state == SET_PWD) begin
            led[2] = 1;
        end
        // 密码过简状态亮led4
        if (state == SIM_PWD) begin
            led[4] = 1;
        end
    end

endmodule
