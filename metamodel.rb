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
      puts "connecting #{self.full_name} --#{wire.name}--> #{sink.full_name}"
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

  class Or2 < Circuit
    def initialize name
      super(name)
      self << Input.new("i0")
      self << Input.new("i1")
      self << Output.new("o1")
    end
  end

  class Not < Circuit
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

  GTECH=[And2,Or2,Not,Dff]

  class RandomCircuitGenerator
    def generate params
      circuit=Circuit.new(params[:name])
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
      puts "placing..."
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
      puts "routing..."
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
          puts "no sink candidate. creating output '#{sink.full_name}'"
          source.connect sink
        end
      end
      # handle exceptions
      if sinks.any?
        puts "try to leverage sources with fanout < params[:max_fanout]"
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
        puts "fallback strategy : bypass parameter"
        puts "Need to add #{sinks.size} supplemental inputs to circuit."
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
      code.save_as "#{circuit.name}.dot"
    end
  end

  class VHDLGenerator
    def generate circuit
      code=Code.new
      code << "library ieee;"
      code << "use ieee.std_logic_1164.all;"
      code << "use ieee.numeric_std.all;"
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
      circuit.components.each do |comp|
        comp_entity=comp.class.to_s.split("::").last
        code << "#{comp.name} : entity work.#{comp_entity}"
        code.indent=4
        code << "port map("
        code.indent=6
        comp.inputs.each do |input|
          code << "#{input.name} => #{input.wire.name},"
        end
        comp.outputs.each do |output|
          wire=output.fanout.first
          code << "#{output.name} => #{output.wire.name},"
        end
        code.indent=4
        code << ");"
        code.indent=2
      end
      code.indent=0
      code << "end rtl;"
      filename=code.save_as("#{circuit.name}.vhd")
      puts "saved as '#{filename}'"
    end
  end
end

if $PROGRAM_NAME==__FILE__
  include Proto

  params={
    name: "test",
    ninputs: 3,
    noutputs:12,
    ncomponents: 50,
    max_fanout: 3,
    depth: 10
  }

  circuit=RandomCircuitGenerator.new.generate(params)
  DotGenerator.new.generate circuit
  VHDLGenerator.new.generate circuit
end
