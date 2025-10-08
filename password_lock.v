module password_lock(
    input clk,               // 100MHz ʱ��
    input rstn,              // �͵�ƽ��λ
    input [9:0] sw,          // ���뿪�أ���������(0-9)
    input input_btn,         // ���������
    input confirm_btn,       // ȷ�ϼ�
    input back_btn,          // �˸��
    input admin_btn,         // ����Ա��
    input change_btn,        // �л������
    output reg [15:0] led,   // LED ָʾ
    output reg [7:0] seg,    // ����ܶ�ѡ
    output reg [7:0] an      // �����λѡ
);

    // =======================
    // ��������
    // =======================
    localparam WAIT     = 4'd0;
    localparam INPUT    = 4'd1;
    localparam UNLOCK   = 4'd2;
    localparam ALARM    = 4'd3;
    localparam SET_PWD  = 4'd4;
    localparam ERROR    = 4'd5;    // ������ʾ״̬
    localparam FINAL_ERROR = 4'd6; // ���մ���״̬�������δ���
    localparam SIM_PWD = 4'd7;     // �������״̬

    // ���߱���
    integer i, k;
    reg match_var;                 // ����ƥ������1��ʾƥ�䣬0��ʾ��ƥ��
    reg [3:0] state, next_state;

    // ����洢
    reg [3:0] password [0:5];      // �洢6λ���룬ÿλ4����
    reg [3:0] input_buf [0:5];     // �û����뻺�������洢���������
    reg [3:0] temp_password [0:5]; // ����Ա��������ʱ����ʱ�洢
    reg [2:0] idx;                 // ����ָ�룬��ʾ��ǰ���뵽�ڼ�λ��0-5��
    reg [1:0] fail_count;          // �����������¼������������0-3��
    reg unlocked;                  // ������־��1��ʾ���Ѵ�
    reg alarm;                     // ������־��1��ʾ��Ҫ����
    reg [3:0] current_digit;       // ��ǰѡ�������
    reg digit_valid;               // ������Ч�ź�

    // ��ʱ�� - 32λ�㹻��ʱԼ43�루100MHzʱ�ӣ�
    reg [31:0] idle_timer;         // �޲�����ʱ�������ڳ�ʱ����
    reg [31:0] unlock_timer;       // ����״̬��ʱ��
    reg [31:0] error_timer;        // ������ʾ��ʱ��/��������ʱ��
    reg [31:0] final_error_timer;  // ���մ����ʱ��
    reg blink_flag;                // ��˸��־

    // ��̬ɨ��
    reg [19:0] scan_counter;       // ɨ�����������������ܶ�̬ɨ��
    reg [2:0] scan_sel;            // ��ǰɨ��������������0-5��
    
    // ��ʾ�л���0-���� 1-��
    reg hide_num;
    
    // ����״̬����ʱ
    reg [7:0] countdown_seconds;  // ����ʱ����
    reg [7:0] countdown_tens;     // ����ʱʮλ��
    reg [7:0] countdown_ones;     // ����ʱ��λ��

    // ����ͬ������ؼ��
    reg input_s0, input_s1;        //���������������ͬ���Ĵ���
    reg confirm_s0, confirm_s1;    // ȷ�ϼ�������ͬ���Ĵ���
    reg back_s0, back_s1;          // �˸��������ͬ���Ĵ���  
    reg admin_s0, admin_s1;        // ����Ա��������ͬ���Ĵ���
    reg change_s0, change_s1;      // �л������������ͬ���Ĵ���
    reg input_edge, confirm_edge, back_edge, admin_edge,change_edge; // �����������ź�
    reg [9:0] sw_prev;             // ��һ�ε�swֵ�����ڼ��仯

    // =======================
    // ��ʼ��ȱʡ���� "123456"
    // =======================
    initial begin
        password[0]=4'd1; password[1]=4'd2; password[2]=4'd3;
        password[3]=4'd4; password[4]=4'd5; password[5]=4'd6;
        for (i = 0; i < 6; i = i + 1) begin
            temp_password[i] <= 4'hF;
        end
    end

    // ����״̬����ʱ30s
    always @(*) begin
        countdown_seconds = 8'd0;
        countdown_tens = 8'd0;
        countdown_ones = 8'd0;
        
        if (state == INPUT) begin
            // 15�뵹��ʱ����
            countdown_seconds = 15 - (idle_timer / 100_000_000);
            countdown_tens = countdown_seconds / 10;
            countdown_ones = countdown_seconds % 10;
        end
        else if (state == UNLOCK) begin
            // 30�뵹��ʱ����
            countdown_seconds = 30 - (unlock_timer / 100_000_000);
            countdown_tens = countdown_seconds / 10;
            countdown_ones = countdown_seconds % 10;
        end
        else if (state == ERROR || state == SIM_PWD) begin
            // 3�뵹��ʱ����
            countdown_seconds = 3 - (error_timer / 100_000_000);
            countdown_tens = countdown_seconds / 10;
            countdown_ones = countdown_ones;
        end
    end

    // =======================
    // ͬ����������������������������
    // =======================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            input_s0 <= 0; input_s1 <= 0; input_edge <= 0;
            confirm_s0 <= 0; confirm_s1 <= 0; confirm_edge <= 0;
            back_s0 <= 0; back_s1 <= 0; back_edge <= 0;
            admin_s0 <= 0; admin_s1 <= 0; admin_edge <= 0;
            change_s0 <= 0; change_s1 <= 0; change_edge <= 0;
        end else begin
            // ͬ��
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

            // �����ؼ��
            input_edge <= (input_s0 & ~input_s1);
            confirm_edge <= (confirm_s0 & ~confirm_s1);
            back_edge    <= (back_s0 & ~back_s1);
            admin_edge   <= (admin_s0 & ~admin_s1);
            change_edge   <= (change_s0 & ~change_s1);
        end
    end

    // �л���ʾģʽ
    // =======================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            hide_num <= 0;
        end else if (change_edge) begin
            hide_num <= ~hide_num;
        end
    end

    // =======================
    // ����ƥ������
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
    // ���������ֱ�����
    // =======================
    always @(*) begin
        digit_valid = 1'b0;
        current_digit = 4'hF;
        
        // ����ĸ����ش򿪣�ֱ�Ӷ�Ӧ����0-9
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
    // ״̬ת���߼�
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
                    // ����6λ��������֤
                    if (match_var) begin
                        next_state = UNLOCK;
                    end else begin
                        if (fail_count == 2) begin
                            next_state = FINAL_ERROR; // �����δ���
                        end else begin
                            next_state = ERROR; // ��һ��ڶ��δ���
                        end
                    end
                end else if (admin_edge && sw == 10'b0000001111) begin
                    next_state = SET_PWD;
                end
                
                // INPUT״̬15���޲������صȴ�״̬
                if (idle_timer >= 15*100_000_000) begin
                    next_state = WAIT;
                end
            end

            UNLOCK: begin
                if (unlock_timer >= 30*100_000_000) begin
                    next_state = WAIT;
                end else if (admin_edge && sw == 10'b0000001111) begin
                    next_state = SET_PWD;
                end else if (confirm_edge) begin // �û�����ȷ�����ص��ȴ�״̬
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
                    next_state = WAIT; // ����Ա�����˳�
                end
            end
            
            ERROR: begin
                if (error_timer >= 3*100_000_000) begin
                    next_state = INPUT; // 3���ص�����״̬
                end
            end
            
            FINAL_ERROR: begin
                // �����δ����һֱ��˸��ֱ������Ա����
                if (admin_edge && sw == 10'b0000001111) next_state = WAIT;
            end

            SIM_PWD: begin
                //��������led4��3s���ص���������״̬
                if (error_timer >= 3*100_000_000) begin
                    next_state = SET_PWD; 
                end 
            end
            
            default: next_state = WAIT;
        endcase
    end

    // =======================
    // ��ʱ����״̬�Ĵ�
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
            // ��λʱ��������Ϊ��ʼ���� "123456"
            password[0] <= 4'd1; password[1] <= 4'd2; password[2] <= 4'd3;
            password[3] <= 4'd4; password[4] <= 4'd5; password[5] <= 4'd6;
            // ��ʼ�����뻺����
            for (i = 0; i < 6; i = i + 1) begin
                input_buf[i] <= 4'hF;
                temp_password[i] <= 4'hF;
            end
        end else begin
            state <= next_state;

            // ���� idle_timer - ֻ��INPUT״̬����޲���
            if (state == INPUT) begin
                if (input_edge || confirm_edge || back_edge || admin_edge || (sw != sw_prev)) begin
                    idle_timer <= 0;
                end else
                    idle_timer <= idle_timer + 1;
            end else begin
                idle_timer <= 0;
            end

            // unlock_timer ���� UNLOCK ״̬����
            if (state == UNLOCK) begin
                unlock_timer <= unlock_timer + 1;
            end else
                unlock_timer <= 0;

            // error_timer �� ERROR ״̬����
            if (state == ERROR || state == SIM_PWD) begin
                error_timer <= error_timer + 1;
            end else
                error_timer <= 0;

            // final_error_timer �� FINAL_ERROR ״̬����
            if (state == FINAL_ERROR) begin
                final_error_timer <= final_error_timer + 1;
                
                // ��˸���ƣ�0.5�����ڣ�- ��FINAL_ERROR״̬�³�����˸
                if (final_error_timer % 50_000_000 == 0) begin
                    blink_flag <= ~blink_flag;
                    
                end
                
            end else begin
                final_error_timer <= 0;
                blink_flag <= 0;
            end

            sw_prev <= sw;

            // ����״̬ת��ʱ�������߼�
            case (next_state)
                WAIT: begin
                    if (state == SET_PWD && confirm_edge) begin
                        // ����������� - ������������
                        for (i = 0; i < 6; i = i + 1) begin
                            password[i] <= temp_password[i];
                        end
                    end
                    if (state != WAIT) begin
                        // ����ȴ�״̬ʱ�������б���
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
                        // ��ERROR״̬�ص�INPUTʱ�����������
                        idx <= 0;
                        for (i = 0; i < 6; i = i + 1) input_buf[i] <= 4'hF;
                    end
                    
                    // ȷ�ϼ�����
                    if (confirm_edge && state == INPUT && digit_valid) begin
                        if (idx < 6) begin
                            // �̶���ǰλ���ƶ�����һλ
                            input_buf[idx] <= current_digit;
                            idx <= idx + 1;
                        end
                    end
                    
                    // �˸������
                    if (back_edge && state == INPUT && idx > 0) begin
                        idx <= idx - 1;
                        input_buf[idx] <= 4'hF;
                    end
                end
                
                UNLOCK: begin
                    // ����״̬����
                    unlocked <= 1;
                    fail_count <= 0;
                end
                
                ALARM: begin
                    alarm <= 1;
                end
                
                SET_PWD: begin
                    // ������������״̬ʱ��������
                    if (state != SET_PWD) begin
                        idx <= 0;
                        for (i = 0; i < 6; i = i + 1) begin
                            temp_password[i] <= 4'hF;
                        end
                    end
                    
                    // ����Ա��������
                    if (confirm_edge && idx < 6 && digit_valid) begin
                        temp_password[idx] <= current_digit;
                        idx <= idx + 1;
                    end

                        // �˸������
                    if (back_edge && idx > 0) begin
                        idx <= idx - 1;
                        temp_password[idx] <= 4'hF;
                    end
                    
                end
                
                ERROR: begin
                    // ����ERROR״̬ʱ���Ӵ������
                    if (state == INPUT) begin
                        fail_count <= fail_count + 1;
                    end
                end
                
                FINAL_ERROR: begin
                    // ����FINAL_ERROR״̬ʱ���ô�������ͱ���
                    if (state == INPUT) begin
                        alarm <= 1;
                    end
                end
            endcase
        end
    end

    // =======================
    // ����ܶ�̬ɨ����ʾ
    // =======================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            scan_counter <= 0;
            scan_sel <= 0;
        end else begin
            scan_counter <= scan_counter + 1;
            if (scan_counter[12:0] == 0) begin      // ÿ8192��ʱ�����ڴ���һ��
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

        // ѡ��Ҫ��ʾ�������
        if (scan_sel < 6) begin
            an[5 - scan_sel] = 0;
        end else if (scan_sel == 6|7) begin
            an[scan_sel] = 0;
        end

        case (state)
            ERROR: begin
                // ��ʾ "Error"��AN5=E, AN4=r, AN3=r, AN2=o, AN1=r
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
                // ������ʼ��˸��ʾ8��H����1s��0.5s
                if (blink_flag) begin
                    // ������ʾH
                    seg = 8'b10001001; // H
                end else begin
                    // ��
                    seg = 8'b11111111;
                end
                // ��������ܶ���ʾ��ͬ����
                an = 8'b00000000;
            end
            
            SET_PWD: begin
                // ����Ա��������ʱʵʱ��ʾ�����û�����һ��
                if (scan_sel < idx && idx <=5) begin
                    if (hide_num) begin
                        // ����������ʾ��
                        seg = seg_decode(4'hE);
                    end else begin
                        // ��ʾ�ѹ̶�������
                        seg = seg_decode(temp_password[scan_sel]);
                    end
                end else if (scan_sel == idx && state == INPUT && idx <= 5) begin
                    if (hide_num) begin
                        // ����������ʾ��
                        seg = seg_decode(4'hE);
                    end else begin
                        // ��ʾ��ǰ���������
                        seg = seg_decode(current_digit);
                    end
                end else begin
                    // ��ʾ���
                    seg = seg_decode(4'hF);
                end
            end
            
            UNLOCK: begin
                // ������ʾ�������ݣ����ұ������������ʾ����ʱ
                if (scan_sel == 7) begin
                    // ��5���������ʾ����ʱʮλ��
                    seg = seg_decode(countdown_tens);
                end else if (scan_sel == 6) begin
                    // ��6���������ʾ����ʱ��λ��
                    seg = seg_decode(countdown_ones);
                end
            end
            
            default: begin
                // ������ʾ�������ݣ����ұ������������ʾ����ʱ
                if (scan_sel < idx && idx <= 5) begin 
                    if (hide_num) begin
                        // ����������ʾ��
                        seg = seg_decode(4'hE);
                    end else begin
                        // ��ʾ�ѹ̶�������
                        seg = seg_decode(input_buf[scan_sel]);
                    end
                end else if (scan_sel == idx && state == INPUT && idx <= 5) begin
                    if (hide_num) begin
                        // ����������ʾ��
                        seg = seg_decode(4'hE);
                    end else begin
                        // ��ʾ��ǰ���������
                        seg = seg_decode(current_digit);
                    end
                end else if (scan_sel == 7) begin
                    // ��5���������ʾ����ʱʮλ��
                    seg = seg_decode(countdown_tens);
                end else if (scan_sel == 6) begin
                    // ��6���������ʾ����ʱ��λ��
                    seg = seg_decode(countdown_ones);
                end else begin
                    // ��ʾ���
                    seg = seg_decode(4'hF);
                end
            end
            
        endcase
    end

    // ����ܶ�����뺯��
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
            default: seg_decode = 8'b11111111; // ȫ��
        endcase
    endfunction

    // =======================
    // LED ָʾ
    // =======================
    always @(*) begin
        led = 16'h0000;
        // ����״̬��led0
        if (state == UNLOCK) begin
            led[0] = 1;
        end
        // ����״̬��led15
        if (state == ALARM || state == FINAL_ERROR) begin
            led[15] = 1;
        end
        // ����Ա״̬��led2
        if (state == SET_PWD) begin
            led[2] = 1;
        end
        // �������״̬��led4
        if (state == SIM_PWD) begin
            led[4] = 1;
        end
    end

endmodule
