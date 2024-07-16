module cache #(
    parameter   DATA_NUM    = 256 ,
    parameter   WAY_NUM   = 2 ,
    parameter   AW          = $clog2(DATA_NUM) 
)(
    input               clk    ,
    input               resetn ,
    // 
    input               valid  ,
    input               op     ,
    input   [7:0]       index  ,
    input   [19:0]      tag    ,
    input   [3:0]       offset ,
    input   [3:0]       wstrb  ,
    input   [31:0]      wdata  ,
    output              addr_ok,
    output              data_ok,
    output  [31:0]    rdata  ,

    // 
    output   rd_req   ,
    output   rd_type  ,
    output   [31:0]    rd_addr  ,
    input   rd_rdy   ,
    input   ret_valid,
    input   ret_last ,
    input   [31:0]  ret_data ,

    output   wr_req  ,
    output   [2:0]  wr_type ,
    output   [31:0]wr_addr ,
    output   [3:0]  wr_wstrb,
    output   [127:0]   wr_data ,
    input   wr_rdy 
);
    genvar i , j ;
    int m , n ;

    wire                wr_op ;
    wire                rd_op ;
    wire                rd_conflict ;
    wire                replace_rd ;
    wire                lookup_rd ;
    wire                rdreq_lookup_rd ;
    wire                hitwrite_wr ;

    wire [7:0]          replace_index ;
    reg                 replace_way ;
    wire [19:0]         replace_tag ;
    reg                 dirty_flag ;

    // refill bus to data_sram 
    wire                refill_wr ;
    wire [7:0]          refill_index ;
    wire [19:0]         refill_tag ;
    wire [1:0]          refill_bank ;
    wire [3:0]          refill_wstrb ;
    wire [31:0]         refill_data ;
    wire [0:1]               refill_way ;

    wire                tagv_rd ;
    wire                tagv_wr ;
    wire    [AW-1:0]    tagv_index ;
    wire    [0:WAY_NUM-1]            tagv_way ;
    wire    [20:0]      tagv_d ;

    wire                data_rd ;
    wire                data_wr ;
    wire    [AW-1:0]    data_index ;
    wire    [3:0]       data_wstrb ;
    wire    [0:WAY_NUM-1]   data_way ;
    wire    [1:0]   data_offset ;
    wire    [31:0]            data_d ;
    
    wire                req_buf_up_en ;
    reg     [68:0]      request_buf ;
    wire                op_1d     ;
    wire    [7:0]       index_1d  ;
    wire    [19:0]      tag_1d    ;
    wire    [3:0]       offset_1d ;
    wire    [3:0]       wstrb_1d  ;
    wire    [31:0]      wdata_1d  ;
    reg     [31:0]      local_rdata ;
    wire    [31:0]      return_data ;
    // hwrite
    reg             wbuf_vld ;
    reg  [49:0]     write_buf ;
    wire [31:0]     wbuf_data ;
    wire [3:0]      wbuf_strb ;
    wire [3:0]      wbuf_offset ;
    wire [7:0]      wbuf_index ;
    wire [0:WAY_NUM-1]          wbuf_way ;
    // miss buf
    reg [1:0]   return_cnt ;
    // sram interface
    wire    [0:WAY_NUM-1][3:0]          sram_data_rd ;
    wire    [0:WAY_NUM-1][3:0]          sram_data_wsel ;
    wire    [0:WAY_NUM-1][3:0]          sram_data_wr ;
    wire    [0:WAY_NUM-1][3:0][AW-1:0]  sram_data_index ;
    wire    [0:WAY_NUM-1][3:0][3:0]     sram_data_wstrb ;
    wire    [0:WAY_NUM-1][3:0][31:0]    sram_data_d ;
    wire    [0:WAY_NUM-1][3:0][31:0]    sram_data_q ;

    wire    [0:WAY_NUM-1]           sram_tagv_rd ;
    wire    [0:WAY_NUM-1]           sram_tagv_wr ;
    wire    [0:WAY_NUM-1][AW-1:0]   sram_tagv_index ;
    wire    [0:WAY_NUM-1][20:0]     sram_tagv_d ;
    wire    [0:WAY_NUM-1][20:0]     sram_tagv_q ;
    // bus
    reg     wr_req ;
    reg     rd_req ;
   //
    reg     [0:WAY_NUM-1][DATA_NUM-1:0]  d_table ;
    wire    [0:WAY_NUM-1][19:0]   tag_sel ;
    wire    [0:WAY_NUM-1]         valid_sel ;
    wire    [0:WAY_NUM-1]         tag_hit ;
    wire                          req_hit ;
    
  //
    enum reg [2:0]  {
        M_IDLE    = 0 ,
        M_LOOKUP  = 1 ,
        M_MISS    = 2 ,
        M_REPLACE = 3 ,
        M_REFILL  = 4 } main_st , main_nst ;

    enum reg {
        H_IDLE    = 0 ,
        H_WRITE  = 1 } hit_st , hit_nst ;
  // TODO
    wire  lfsr_data ;
    reg   rand_data ;
    assign lfsr_data = rand_data ;
    always @(posedge clk)
        if(!resetn)
            rand_data <= 0 ;
        else if(main_st==M_LOOKUP & main_nst==M_MISS)
            rand_data <= $random();//index[0] ;
   // 
    
    assign rdreq_lookup_rd  = main_nst==M_LOOKUP && rd_op ;
    assign lookup_rd        = main_nst==M_LOOKUP ;
    assign hitwrite_wr      = wbuf_vld ;
    assign wr_op            = valid & op ;
    assign rd_op            = valid & !op ;

    assign replace_rd       = main_nst==M_REPLACE & main_st==M_MISS ;
    assign replace_index    = index_1d ;
    assign replace_bank     = 4'b1111 ;

    assign refill_wr        = ret_valid ; 
    assign refill_index     = replace_index ; 
    assign refill_tag       = tag_1d ;
    assign refill_bank      = return_cnt ;
    assign refill_way       = replace_way ? 2'b01 : 2'b10 ; //TODO 
    assign refill_data      = op_1d&(refill_bank==offset_1d[3:2]) ? wdata_1d : ret_data ;
    assign refill_wstrb     = wstrb_1d ;

    assign tagv_rd     = lookup_rd | replace_rd ;
    assign tagv_wr     = refill_wr ;
    assign tagv_index   = lookup_rd ? index :
                         replace_rd ? replace_index :
                                      refill_index ;
    assign tagv_way     = lookup_rd ? {WAY_NUM{1'b1}} :
                          replace_rd ? replace_way : 
                                       refill_way ;
    assign tagv_d       = {tag_1d,1'b1} ;

    assign data_rd     = rdreq_lookup_rd | replace_rd ;
    assign data_wr     = refill_wr | hitwrite_wr ;
    assign data_index   = rdreq_lookup_rd ? index : 
                               replace_rd ? replace_index :
                                refill_wr ? refill_index :
                                            wbuf_index ;

    assign data_wstrb  = refill_wr ? refill_wstrb : wbuf_strb ;  
    assign data_offset = refill_wr ? refill_bank : wbuf_offset[3:2] ;
    assign data_way    = refill_wr ? refill_way : wbuf_way ;
    assign data_d      = refill_wr ? refill_data : wbuf_data ;
    
    // look up logic
    assign req_buf_up_en = main_nst==M_LOOKUP ;
    always @(posedge clk) 
        if(req_buf_up_en)
            request_buf = {op,
                           index,
                           tag,
                           offset,
                           wstrb,
                           wdata};

    assign {
            op_1d,
            index_1d,
            tag_1d,
            offset_1d,
            wstrb_1d,
            wdata_1d 
            } = request_buf ;

    generate 
        for(i=0;i<WAY_NUM;i++) begin
            assign tag_sel[i]   = sram_tagv_q[i][20:1] ;
            assign valid_sel[i] = sram_tagv_q[i][0] ;
            assign tag_hit[i]   = (tag_1d==tag_sel[i]) & valid_sel[i] ;
        end
    endgenerate
    assign req_hit  = |tag_hit ;
    
    always @(*) begin
        local_rdata = 0 ;
        for(m=0;m<WAY_NUM;m++)
            for(n=0;n<4;n++)
                local_rdata = local_rdata | (sram_data_q[m][n] & {32{tag_hit[m] & n==offset_1d[3:2]}}) ;
    end

    // hit write to sram logic  
    always @(posedge clk) 
        if(hit_nst==H_WRITE)
            write_buf <= {wdata_1d , index_1d , offset_1d , wstrb_1d , tag_hit} ;

    always @(posedge clk) 
        if(!resetn)
            wbuf_vld <= 0 ;
        else if(hit_nst==H_WRITE)
            wbuf_vld <= 1 ;
        else if(hit_nst==H_IDLE)
            wbuf_vld <=  0 ;
    
    assign {wbuf_data,wbuf_index,wbuf_offset,wbuf_strb,wbuf_way} = write_buf ;
    
    // miss logic
    assign replace_tag = sram_tagv_q[replace_way][20:1] ; // 

    always @(posedge clk) 
        if(main_st==M_LOOKUP & main_nst==M_MISS) begin
            replace_way  <= lfsr_data  ;
            dirty_flag   <= d_table[lfsr_data][index_1d] ;
        end

    // replace logic
    assign  wr_data = sram_data_q[replace_way] ;
    assign  wr_addr = {replace_tag,replace_index,4'd0} ;    
    assign  wr_type = 3'b100 ; // req line
    assign  wr_wstrb = 4'hF ;
    
    always @(posedge clk) 
        if(!resetn)
            wr_req <= 0 ;
        else if(main_st==M_MISS & main_nst==M_REPLACE)
            wr_req <= 1 ;
        else if(wr_rdy)
            wr_req <= 0 ;

    // refill logic
    assign rd_addr = {refill_tag,refill_index,4'd0} ;
    assign rd_type = 3'b100 ; //req line

    always @(posedge clk) 
        if(!resetn)
            rd_req <= 0 ;
        else if(main_st==M_MISS & !dirty_flag)
            rd_req <= 1 ;
        else if(main_st==M_REPLACE)
            rd_req <= 1 ;
        else  
            rd_req <= 0 ;

    always @(posedge clk) 
        if(!resetn)
            return_cnt <= 0 ;
        else if(ret_valid & ret_last)
            return_cnt <= 0 ;
        else if(ret_valid & !ret_last)
            return_cnt <= return_cnt + 1 ;
    

    generate 
        for(i=0;i<WAY_NUM;i++) begin 
            for(j=0;j<4;j++) begin
                assign sram_data_rd[i][j]   = data_rd ;
                assign sram_data_wsel[i][j] = data_offset==j & data_way[i] ;
                assign sram_data_wr[i][j]   = data_wr & sram_data_wsel[i][j] ;
                assign sram_data_index[i][j] = data_index ;
                assign sram_data_wstrb[i][j] = data_wstrb ;
                assign sram_data_d[i][j]    = data_d & {32{sram_data_wsel[i][j]}} ;

                SRAM_MDL #(
                    .DEPTH  (256    ) ,
                    .BW     (32     ) ,
                    .NUM    (4      )
                ) data_sram_u(
                    .clk    (clk    ) ,
                    .resetn (resetn ) ,
                    .cen    (!(sram_data_rd[i][j]|sram_data_wr[i][j])   ) ,
                    .wen    (!sram_data_wr[i][j]   ) ,
                    .wemn   (sram_data_wstrb[i][j] ) ,
                    .d      (sram_data_d[i][j]     ) ,
                    .addr   (sram_data_index[i][j]  ) ,
                    .q      (sram_data_q[i][j]     )
                );

            end
                assign sram_tagv_rd[i]   = tagv_rd ;
                assign sram_tagv_wr[i]   = tagv_wr & tagv_way[i];
                assign sram_tagv_index[i] = tagv_index ;
                assign sram_tagv_d[i]    = tagv_d ;

                SRAM_MDL #(
                    .DEPTH  (256    ) ,
                    .BW     (21     ) ,
                    .NUM    (1      )
                ) tagv_sram_u(
                    .clk    (clk    ) ,
                    .resetn (resetn ) ,
                    .cen    (!(sram_tagv_rd[i]|sram_tagv_wr[i])   ) ,
                    .wen    (!sram_tagv_wr[i]          ) ,
                    .wemn   (1'b1                      ) ,
                    .d      (sram_tagv_d[i]            ) ,
                    .addr   (sram_tagv_index[i]         ) ,
                    .q      (sram_tagv_q[i]            )
                );

            always @(posedge clk) 
                if(!resetn)
                    d_table[i] <= 0 ;
                else if(wbuf_vld && wbuf_way==i) // cache hit write 
                    d_table[i][wbuf_index] <= 1 ;
                else if(main_st==M_REFILL && replace_way==i && op_1d)
                    d_table[i][refill_index] <= 1 ;
                else if(main_st==M_REFILL && replace_rd==i && !op_1d)
                    d_table[i][refill_index] <= 0 ;
        end
    endgenerate
    
    // main state machine logic
    assign rd_conflict  = wbuf_vld && (offset==offset_1d) ;

    always @(*) begin
        case(main_st)
            M_IDLE      : main_nst = wr_op || (rd_op & !rd_conflict)  ? M_LOOKUP : M_IDLE ;
            M_LOOKUP    : main_nst = !req_hit ? M_MISS :
                                     !valid || (rd_op&rd_conflict) ? M_IDLE : M_LOOKUP ;
            M_MISS      : main_nst = !dirty_flag ? rd_rdy ?  M_REFILL : M_MISS :  
                                                   wr_rdy ? M_REPLACE : M_MISS ;
            //M_MISS      : main_nst = wr_rdy ? M_REPLACE : M_MISS ;
            M_REPLACE   : main_nst = rd_rdy ? M_REFILL : M_REPLACE ;
            M_REFILL    : main_nst = (ret_valid & ret_last) ? M_IDLE : M_REFILL ;
            default     : main_nst = M_IDLE ;
        endcase
    end

    always @(posedge clk) 
        if(!resetn)
            main_st <= M_IDLE ;
        else 
            main_st <= main_nst ;

    // hit state machine logic
    always @(*) begin
        case(hit_st)
            H_IDLE : hit_nst = main_st==M_LOOKUP & req_hit & op_1d ? H_WRITE : H_IDLE ;
            H_WRITE: hit_nst = main_st==M_LOOKUP & req_hit & op_1d ? H_WRITE : H_IDLE ;
            default: hit_nst = H_IDLE ;
        endcase
    end

    always @(posedge clk) 
        if(!resetn)
            hit_st <= H_IDLE ;
        else 
            hit_st <= hit_nst ;
      
    assign addr_ok = main_st==M_IDLE ||
                     main_st==M_LOOKUP && main_nst==M_LOOKUP ;
    assign data_ok = main_st==M_LOOKUP && req_hit ||
                     main_st==M_LOOKUP && op_1d ||
                     main_st==M_REFILL && !op_1d && ret_valid && (return_cnt==offset_1d[3:2]) ;
    assign rdata   = main_st==M_LOOKUP && req_hit ? local_rdata : ret_data ;

endmodule
