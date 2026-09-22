// ---------------------------------------------------------------
//   Protocol checks (simulation only): flag illegal flit sequences
//   loudly instead of letting them fail silently. Neither condition
//   corrupts data -- both are already refused by the "want" logic
//   above -- but a sender producing either has a real bug worth
//   finding in verification, not discovering as an unexplained stall.
//   ---------------------------------------------------------------
//   synthesis translate_off
  always @(posedge clk) begin
      if (rst_n) begin
          for (i = 0; i < 5; i = i + 1) begin
              if (!route_active[i] && in_valid[i] && p_in_type[i] == BODY)
                  $display("%0t PROTOCOL ERROR: port %0d sent a BODY flit with no preceding Head (stray flit) -- will stall forever, never granted", $time, i);
              if (!route_active[i] && in_valid[i] && p_in_type[i] == TAIL)
                  $display("%0t PROTOCOL ERROR: port %0d sent a TAIL flit with no preceding Head (stray flit) -- will stall forever, never granted", $time, i);
              if (route_active[i] && in_valid[i] && p_in_type[i] == HEAD)
                  $display("%0t PROTOCOL ERROR: port %0d sent a HEAD flit while a route was already held (dest=%0d) -- refused, not silently misrouted", $time, i, route_dest[i]);
              if (route_active[i] && in_valid[i] && p_in_type[i] == HEADTAIL)
                  $display("%0t PROTOCOL ERROR: port %0d sent a HEADTAIL flit while a route was already held (dest=%0d) -- refused, not silently misrouted", $time, i, route_dest[i]);
          end
      end
  end
  // synthesis translate_on