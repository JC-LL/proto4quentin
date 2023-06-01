def step str
  print str
  $stdin.gets
end

module Proto

  class Wire
    @@id=0
    attr_accessor :name
    def initialize
      @name="w#{@@id+=1}"
    end
  end

  class Port
    attr_accessor :name,:owner
    attr_accessor :fanin,:fanout
    attr_accessor :wire

    def initialize name
      @name=name
      @fanin,@fanout=[],[]
      @wire=Wire.new
    end

    def connect sink
      @fanout << sink
      sink.fanin << self
      #puts "connecting #{self.full_name} --#{wire.name}--> #{sink.full_name}"
    end

    def full_name
      "#{owner.name}.#{name}"
    end
  end

  class Input < Port
  end

  class Output < Port
  end

  class Circuit
    attr_accessor :name
    attr_accessor :inputs,:outputs
    attr_accessor :owner #enclosing component
    attr_accessor :components

    def initialize name
      @name=name
      @inputs=[]
      @outputs=[]
      @components=[]
    end

    def <<(element)
      element.owner=self
      case element
      when Input
        @inputs << element
      when Output
        @outputs << element
      when Circuit
        @components << element
      end
    end
  end

  class And2 < Circuit
    def initialize name
      super(name)
      self << Input.new("i0")
      self << Input.new("i1")
      self << Output.new("o1")
    end
  end

  class And3 < Circuit
    def initialize name
      super(name)
      self << Input.new("i0")
      self << Input.new("i1")
      self << Input.new("i2")
      self << Output.new("o1")
    end
  end

  class Or2 < Circuit
    def initialize name
      super(name)
      self << Input.new("i0")
      self << Input.new("i1")
      self << Output.new("o1")
    end
  end

  class Inv < Circuit
    def initialize name
      super(name)
      self << Input.new("i0")
      self << Output.new("o1")
    end
  end

  class Dff < Circuit
    def initialize name
      super(name)
      self << Input.new("D")
      self << Output.new("Q")
    end
  end

  GTECH=[And2,And3,Or2,Inv,Dff]

  class RandomCircuitGenerator
    def generate params
      circuit=Circuit.new(name=params[:name])
      puts "[+] generating random circuit '#{name}'"
      params[:ninputs].times{|i|  circuit << Input.new("i_#{i}")}
      params[:noutputs].times{|i| circuit << Output.new("o_#{i}")}
      params[:ncomponents].times do |i|
        type=GTECH.sample
        instance_name="#{type.to_s.split("::").last.downcase}_#{i}"
        circuit << type.new(instance_name)
      end
      place params,circuit
      route params,circuit
      circuit
    end


    def place params,circuit
      puts "[+] placing..."
      @level={}
      depth=params[:depth]
      circuit.inputs.each {|i| @level[i]=0}
      circuit.outputs.each{|o| @level[o]=depth+1}
      circuit.components.each do |comp|
        level=1+rand(depth)
        comp.inputs.each{|i| @level[i]=level}
        comp.outputs.each{|o| @level[o]=level}
      end
    end

    def max_idx io,circuit
      circuit.send(io).map{|o| o.name.match(/_(\d+)/)[1].to_i}.max
    end

    def route params,circuit
      puts "[+] routing..."
      sources=(circuit.inputs  + circuit.components.map{|c| c.outputs}).flatten
      sinks  =(circuit.outputs + circuit.components.map{|c| c.inputs}).flatten
      # base cases :
      sources.each do |source|
        candidate_sinks=sinks.select{|sink| @level[sink] > @level[source]}
        candidate_sinks << sinks.select{|sink| sink.owner.is_a?(Dff)}
        candidate_sinks.flatten!
        candidate_sinks.reject!{|sink| sink.owner==source.owner}
        fanout=1+ rand(params[:max_fanout])
        candidate_sinks.sample(fanout).each do |sink|
          # prevent connection of a same source to several circuit outputs
          unless source.fanout.size!=0 and sink.owner==circuit
            source.connect sink
            sinks.delete sink
          end
        end
        if candidate_sinks.empty?
          # add supplemental output at will.
          max_idx=max_idx(:outputs,circuit)
          out_name="o_#{max_idx+1}"
          circuit << sink=Output.new(out_name)
          puts "  |--[+] no sink candidate. creating output '#{sink.full_name}'"
          source.connect sink
        end
      end
      # handle exceptions
      if sinks.any?
        puts "  |--[+] try to leverage sources with fanout < params[:max_fanout]"
        candidate_sources=sources.select{|source| source.fanout.size < params[:max_fanout]}
        sinks.each do |sink|
          candidate_sources.reject!{|source| @level[source] >= @level[sink]}
          if candidate_sources.any?
            source=candidate_sources.shift
            source.connect sink
            sinks.delete sink
          end
        end
      end
      if sinks.any?
        puts "  |--[+] fallback strategy : bypass parameter"
        puts "      |--[+] Need to add #{sinks.size} supplemental inputs to circuit."
        sinks.size.times do |i|
          sink=sinks.shift
          max_idx=max_idx(:inputs,circuit)
          in_name="i_#{max_idx+1}"
          circuit << source=Input.new(in_name)
          source.connect sink
        end
      end
    end
  end

  require_relative "code"

  class DotGenerator
    def generate circuit
      code=Code.new
      code << "digraph #{circuit.name} {"
      code.indent=2
      code << "graph [rankdir = LR];"
      ports=[circuit.inputs,circuit.outputs].flatten
      ports.each do |port|
        code << "#{port.name}[shape=cds,xlabel=\"#{port.name}\"]"
      end

      circuit.components.each do |component|
        inputs =component.inputs.map {|port| "<#{port.name}>#{port.name}"}.join("|")
        outputs=component.outputs.map{|port| "<#{port.name}>#{port.name}"}.join("|")
        fanin ="{#{inputs}}"
        fanout="{#{outputs}}"
        label ="{#{fanin}| #{component.name} |#{fanout}}"
        code << "#{component.name}[shape=record; style=filled;color=cadetblue; label=\"#{label}\"]"
      end

      sources=(circuit.inputs  + circuit.components.map{|c| c.outputs}).flatten
      sources.each do |source|
        source_name= source.owner==circuit ? source.name : [source.owner.name,source.name].join(":")
        wire=source.wire
        source.fanout.each do |sink|
          sink_name  = sink.owner  ==circuit ? sink.name   : [sink.owner.name,sink.name].join(":")
          code << "#{source_name} -> #{sink_name}[label=\"#{wire.name}\"]"
        end
      end

      code.indent=0
      code << "}"
      filename=code.save_as("#{circuit.name}.dot")
      puts "[+] generated '#{filename}'"
    end
  end

  class VHDLGenerator

    def gen_gtech
      puts "[+] generating VHDL gtech "
      GTECH.each do |circuit_klass|
        circuit_name=circuit_klass.to_s.split('::').last.downcase
        case circuit_klass
        when Inv
          func_code="o0 <= not i0 after delay;"
        when Dff
          func_code=Code.new
          func_code << "process(clk)"
          func_code.indent=2
          func_code << "if rising_edge(clk) then"
          func_code.indent=4
          func_code << "q <= d;"
          func_code.indent=2
          func_code << "end if;"
          func_code.indent=0
          func_code << "end process;"
        else
          mdata=circuit_name.match(/\A(\D+)(\d*)/)
          op=mdata[1]
          card=(mdata[2] || "0").to_i
          circuit_instance=circuit_klass.new("test")
          assign_lhs=circuit_instance.outputs.first.name
          assign_rhs=circuit_instance.inputs.map{|input| input.name}.join(" #{op} ")
          assign_rhs="not #{assign_rhs}" if op=="not"
          assign="#{assign_lhs} <= #{assign_rhs} after delay;"
          func_code=assign
        end

        code=Code.new
        code << "--generated automatically"
        code << ieee_header
        code.newline
        code << "entity #{circuit_name} is"
        code.indent=2
        code << "generic(delay : time := 1 ns);"
        code << "port("
        code.indent=4
        if circuit_instance.is_a?(Dff)
          code << "clk : in std_logic;"
        end
        circuit_instance.inputs.each do |input|
          code << "#{input.name} : in  std_logic;"
        end
        circuit_instance.outputs.each do |output|
          code << "#{output.name} : out std_logic;"
        end
        code.indent=2
        code << ");"
        code.indent=0
        code << "end #{circuit_name};"
        code.newline
        code << "architecture rtl of #{circuit_name} is"
        code << "begin"
        code.indent=2
        code << func_code
        code.indent=0
        code << "end rtl;"

        filename=code.save_as("#{circuit_name}.vhd")
        puts " |--[+] generated '#{filename}'"
      end
    end

    def ieee_header
      code=Code.new
      code << "library ieee;"
      code << "use ieee.std_logic_1164.all;"
      code << "use ieee.numeric_std.all;"
      code
    end

    def generate circuit
      code=Code.new
      code << ieee_header
      code.newline
      code << "library gtech_lib;"
      code.newline
      code << "entity #{circuit.name} is"
      code.indent=2
      code << "port("
      code.indent=4
      code << "clk : in  std_logic;"
      circuit.inputs.each{|i|  code << "#{i.name} : in  std_logic;"}
      circuit.outputs.each{|o| code << "#{o.name} : out std_logic;"}
      code.indent=2
      code << ");"
      code.indent=0
      code << "end #{circuit.name};"
      code.newline
      code << "architecture rtl of #{circuit.name} is"
      code.indent=2
      sources=(circuit.inputs + circuit.components.map{|comp| comp.outputs}).flatten
      signals=sources.map(&:wire)
      signals.each do |sig|
        code << "signal #{sig.name} : std_logic;"
      end
      code.indent=0
      code << "begin"
      code.indent=2
      code << "----------------------------------"
      code << "-- input to wire connexions "
      code << "----------------------------------"
      circuit.inputs.each do |input|
        code << "#{input.wire.name} <= #{input.name};"
      end
      code << "----------------------------------"
      code << "-- component interconnect "
      code << "----------------------------------"
      circuit.components.each do |comp|
        comp_entity=comp.class.to_s.split("::").last
        code << "#{comp.name} : entity gtech_lib.#{comp_entity}"
        code.indent=4
        code << "port map("
        code.indent=6
        if comp.is_a? Dff
          code << "clk => clk,"
        end
        comp.inputs.each do |input|
          code << "#{input.name} => #{input.fanin.first.wire.name},"
        end
        comp.outputs.each do |output|
          wire=output.fanout.first
          code << "#{output.name} => #{output.wire.name},"
        end
        code.indent=4
        code << ");"
        code.indent=2
        code << "----------------------------------"
        code << "-- input to wire to output connexions "
        code << "----------------------------------"
        circuit.outputs.each do |output|
        code << "#{output.name} <= #{output.fanin.first.wire.name};"
      end
      end
      code.indent=0
      code << "end rtl;"
      filename=code.save_as("#{circuit.name}.vhd")
      puts "[+] generated circuit '#{filename}'"
    end

    def generate_tb circuit,nb_stim
      code=Code.new
      code << "--automatically generated"
      code << ieee_header

      code.newline
      code << "entity #{circuit.name}_tb is"
      code << "end #{circuit.name}_tb;"
      code.newline
      code << "architecture bhv of #{circuit.name}_tb is"
      code.indent=2
      code << "constant HALF_PERIOD : time := 5 ns;"
      code << "signal running : boolean := true;"
      code << "signal reset_n : std_logic;"
      code << "signal clk     : std_logic := '0';"
      code.newline
      circuit.inputs.each do |input|
        code << "signal #{input.name} : std_logic;"
      end
      circuit.outputs.each do |output|
        code << "signal #{output.name} : std_logic;"
      end
      code.newline
      code << decl_stim_vector(circuit,nb_stim)
      code.indent=0

      code << "begin"
      code.newline
      code.indent=2

      code << gen_clk_reset
      code.newline
      code << "dut : entity work.#{circuit.name}"
      code.indent=4
      code << "port map("
      code.indent=6
      code << "clk => clk,"
      circuit.inputs.each do |input|
        code << "#{input.name} => #{input.name},"
      end
      circuit.outputs.each do |output|
        code << "#{output.name} => #{output.name},"
      end
      code.indent=4
      code << ");"
      code.newline
      code.indent=2
      code << gen_stim_process(circuit)
      code.indent=0
      code << "end bhv;"
      filename="#{circuit.name}_tb.vhd"
      code.save_as filename
      puts "[+] generated testbench '#{filename}'"
    end

    def gen_clk_reset
      code=Code.new
      code << "reset_n <= '1','0' after 123 ns;"
      code.newline
      code << "clk <= not(clk) after HALF_PERIOD when running else clk;"
      code
    end

    def gen_stim_process circuit
      code=Code.new
      code << "stim : process"
      code.indent=2
      code << "variable stim_v : stim_type;"
      code.indent=0
      code << "begin"
      code.indent=2
      code << "report(\"waiting for reset_n\");"
      code << "wait until reset_n='1';"
      code << "report(\"starting stimuli sequence\");"
      code << "for i in STIM_VECT'range loop"
      code.indent=4
      code << "wait until rising_edge(clk);"
      code << "stim_v := STIM_VECT(i);"
      circuit.inputs.each do |input|
        code << "#{input.name} <= stim_v.#{input.name};"
      end
      code.indent=2
      code << "end loop;"
      code << "report(\"ending stimuli sequence : \" & integer'image(STIM_VECT'length) & \" stimuli applied\");"
      code << "running <= false;"
      code << "wait;"
      code.indent=0
      code << "end process;"
      code.newline
      code
    end

    def decl_stim_vector circuit,nb_stim
      code=Code.new
      code << "type stim_type is record"
      code.indent=2
      circuit.inputs.each do |input|
        code << "#{input.name} : std_logic;"
      end
      code.indent=0
      code << "end record;"
      code.newline
      code << "type stim_vect_type is array(0 to #{nb_stim-1}) of stim_type;"
      code.newline
      code << "constant STIM_VECT : stim_vect_type :=("
      code.indent=2
      nb_stim.times do |i|
        code << gen_stim(circuit)
      end
      code.indent=0
      code << ");"
      code
    end

    def gen_stim circuit
      str=circuit.inputs.map{|input| "#{input.name}=>'#{rand(2)}'"}.join(',')
      "(#{str}),"
    end

    def generate_compile_script circuit
      code=Code.new
      code << "echo \"[+] cleaning\""
      code << "rm -rf *.o #{circuit.name}_tb.ghw #{circuit.name}_tb"
      code << "echo \"[+] compiling gtech\""
      GTECH.each do |klass|
        entity=klass.to_s.downcase.split('::').last
        code << "echo \" |--[+] compiling #{entity}.vhd\""
        code << "ghdl -a --work=gtech_lib #{entity}.vhd"
      end
      code << "echo \"[+] compiling #{circuit.name}.vhd\""
      code << "ghdl -a #{circuit.name}.vhd"
      code << "echo \"[+] compiling testbench #{circuit.name}_tb.vhd\""
      code << "ghdl -a #{circuit.name}_tb.vhd"
      code << "echo \"[+] elaboration\""
      code << "ghdl -e #{circuit.name}_tb"
      code << "echo \"[+] running simulation\""
      code << "ghdl -r #{circuit.name}_tb --wave=#{circuit.name}_tb.ghw"
      code << "echo \"[+] launching viewer on #{circuit.name}_tb.ghw\""
      code << "gtkwave #{circuit.name}_tb.ghw #{circuit.name}_tb.sav"
      code
      filename=code.save_as("compile_#{circuit.name}.x")
      system("chmod +x #{filename}")
    end

    def run_compile_script circuit
      puts "[+] run script..."
      system("./compile_#{circuit.name}.x")
    end
  end
end

if $PROGRAM_NAME==__FILE__
  include Proto
  params={
    name: "test",
    ninputs: 5,
    noutputs:4,
    ncomponents: 50,
    max_fanout: 3,
    depth: 10,
    nstimuli: 100
  }

  circuit=RandomCircuitGenerator.new.generate(params)

  DotGenerator.new.generate circuit
  vhdl=VHDLGenerator.new
  vhdl.gen_gtech
  vhdl.generate circuit
  vhdl.generate_tb circuit,nbstim=100
  vhdl.generate_compile_script circuit
  vhdl.run_compile_script circuit
end
