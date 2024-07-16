module tlb #(
    parameter TLB_NUM = 16 ,
    parameter IDX_W   = $clog2(TLB_NUM)
)(
    input   clk ,
    // search 
    input   [18:0]  s0_vpn2 ,
    input           s0_odd_page ,
    input   [7:0]   s0_asid ,
    output          s0_found ,
    output  [IDX_W-1:0] s0_index ,
    output  [19:0]  s0_pfn ,
    output  [2:0]   s0_c ,
    output          s0_d ,
    output          s0_v ,
    // search 
    input   [18:0]  s1_vpn2 ,
    input           s1_odd_page ,
    input   [7:0]   s1_asid ,
    output          s1_found ,
    output  [IDX_W-1:0] s1_index ,
    output  [19:0]  s1_pfn ,
    output  [2:0]   s1_c ,
    output          s1_d ,
    output          s1_v ,
    // write 
    input           wr ,
    input   [IDX_W-1:0] w_index ,
    input   [18:0]  w_vpn2 ,
    input   [7:0]   w_asid ,
    input           w_g ,
    input   [19:0]  w_pfn0 ,
    input   [2:0]   w_c0 ,
    input           w_d0 ,
    input           w_v0 ,
    input   [19:0]  w_pfn1 ,
    input   [2:0]   w_c1 ,
    input           w_d1 ,
    input           w_v1 ,
    // read 
    input   [IDX_W-1:0] r_index ,
    output  [18:0]  r_vpn2 ,
    output  [7:0]   r_asid ,
    output          r_g ,
    output  [19:0]  r_pfn0 ,
    output  [2:0]   r_c0 ,
    output          r_d0 ,
    output          r_v0 ,
    output  [19:0]  r_pfn1 ,
    output  [2:0]   r_c1 ,
    output          r_d1 ,
    output          r_v1
);
    genvar  i ;    
    int j ;

    reg [0:TLB_NUM-1][18:0] tlb_vpn2 ;
    reg [0:TLB_NUM-1][7:0]  tlb_asid ;
    reg [0:TLB_NUM-1]       tlb_g ;
    reg [0:TLB_NUM-1][19:0] tlb_pfn0 ;
    reg [0:TLB_NUM-1][2:0]  tlb_c0 ;
    reg [0:TLB_NUM-1]       tlb_d0 ;
    reg [0:TLB_NUM-1]       tlb_v0 ;
    reg [0:TLB_NUM-1][19:0] tlb_pfn1 ;
    reg [0:TLB_NUM-1][2:0]  tlb_c1 ;
    reg [0:TLB_NUM-1]       tlb_d1 ;
    reg [0:TLB_NUM-1]       tlb_v1 ;

    wire [TLB_NUM-1:0]      match0 ;
    wire [TLB_NUM-1:0]      match1 ;
    reg  [IDX_W-1:0]        index0 ;
    reg  [IDX_W-1:0]        index1 ;
    reg  [19:0]             pfn0 ;
    reg  [2:0]              c0 ;
    reg                     d0 ;
    reg                     v0 ;
    reg  [19:0]             pfn1 ;
    reg  [2:0]              c1 ;
    reg                     d1 ;
    reg                     v1 ;


   // serch logic
    generate
        for(i=0;i<TLB_NUM;i++) begin
            assign match0[i] = (s0_vpn2==tlb_vpn2[i])&(s0_asid==tlb_asid[i] || tlb_g[i]) ;
            assign match1[i] = (s1_vpn2==tlb_vpn2[i])&(s1_asid==tlb_asid[i] || tlb_g[i]) ;
        end
    endgenerate
    
    always @(*) begin : index_gen
        index0 = 0 ;
        index1 = 0 ;
        for(j=0;j<TLB_NUM;j++) begin
            index0 = index0 | (j & {IDX_W{match0[j]}}) ;
            index1 = index1 | (j & {IDX_W{match1[j]}}) ;
        end
    end
    
    always @(*) begin : pfn_gen
        pfn0 = 0 ;
        pfn1 = 0 ;
        for(j=0;j<TLB_NUM;j++) begin
            pfn0 = pfn0 | ({20{match0[j]&!s0_odd_page}} & tlb_pfn0[j]) | ({20{match0[j]&s0_odd_page}} & tlb_pfn1[j]) ;
            pfn1 = pfn1 | ({20{match1[j]&!s1_odd_page}} & tlb_pfn0[j]) | ({20{match1[j]&s1_odd_page}} & tlb_pfn1[j]) ;
        end
    end

    always @(*) begin : c_gen
        c0 = 0 ;
        c1 = 0 ;
        for(j=0;j<TLB_NUM;j++) begin
            c0 = c0 | ({3{match0[j]&!s0_odd_page}} & tlb_c0[j]) | ({3{match0[j]&s0_odd_page}} & tlb_c1[j]) ;
            c1 = c1 | ({3{match1[j]&!s1_odd_page}} & tlb_c0[j]) | ({3{match1[j]&s1_odd_page}} & tlb_c1[j]) ;
        end
    end

    always @(*) begin : v_gen
        v0 = 0 ;
        v1 = 0 ;
        for(j=0;j<TLB_NUM;j++) begin
            v0 = v0 | (match0[j]&!s0_odd_page & tlb_v0[j]) | (match0[j]&s0_odd_page & tlb_v1[j]) ;
            v1 = v1 | (match1[j]&!s1_odd_page & tlb_v0[j]) | (match1[j]&s1_odd_page & tlb_v1[j]) ;
        end
    end

    always @(*) begin : d_gen
        d0 = 0 ;
        d1 = 0 ;
        for(j=0;j<TLB_NUM;j++) begin
            d0 = d0 | (match0[j]&!s0_odd_page & tlb_d0[j]) | (match0[j]&s0_odd_page & tlb_d1[j]) ;
            d1 = d1 | (match1[j]&!s1_odd_page & tlb_d0[j]) | (match1[j]&s1_odd_page & tlb_d1[j]) ;
        end
    end
    
    // read write 
    
    always @(posedge clk)
        if(wr) begin
            tlb_vpn2[w_index] <= w_vpn2 ; 
            tlb_asid[w_index] <= w_asid ;
               tlb_g[w_index] <= w_g ;
            tlb_pfn0[w_index] <= w_pfn0 ; 
              tlb_c0[w_index] <= w_c0 ;
              tlb_d0[w_index] <= w_d0 ;
              tlb_v0[w_index] <= w_v0 ;
            tlb_pfn1[w_index] <= w_pfn1 ;
              tlb_c1[w_index] <= w_c1 ;
              tlb_d1[w_index] <= w_d1 ;
              tlb_v1[w_index] <= w_v1 ;
        end
   
    // s0 search out
    assign s0_found = |match0 ;
    assign s0_index = index0 ;
    assign s0_pfn   = pfn0 ;
    assign s0_c     = c0 ;
    assign s0_d     = d0 ;
    assign s0_v     = v0 ;
    // s1 search out
    assign s1_found = |match1 ;
    assign s1_index = index1 ;
    assign s1_pfn   = pfn1 ;
    assign s1_c     = c1 ;
    assign s1_d     = d1 ;
    assign s1_v     = v1 ;
    // read out
    assign r_vpn2 = tlb_vpn2[r_index] ;
    assign r_asid = tlb_asid[r_index] ;
    assign r_g    = tlb_g[r_index] ;
    assign r_pfn0 = tlb_pfn0[r_index] ; 
    assign r_c0   = tlb_c0[r_index] ;
    assign r_d0   = tlb_d0[r_index] ;
    assign r_v0   = tlb_v0[r_index] ;
    assign r_pfn1 = tlb_pfn1[r_index] ;
    assign r_c1   = tlb_c1[r_index] ;    
    assign r_d1   = tlb_d1[r_index] ; 
    assign r_v1   = tlb_v1[r_index] ;

endmodule 
