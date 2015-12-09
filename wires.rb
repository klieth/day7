
require "unicode"

filename = ARGV[0] || "test.txt"

module Parser
  class Token
    attr_accessor :spelling
    def initialize(line, char)
      @spelling = ""
      @line = line
      @char = char
    end

    def add_char ch
      if char_accepted(ch)
        @spelling << ch
      else
        return nil
      end
    end

    def line
      @line
    end

    def char
      @char
    end

    def to_s
      "(#{self.class} '#{@spelling}' #{@line}:#{@char})"
    end
  end

  class Number < Token
    def char_accepted ch
      ch.match(/\d/)
    end
  end
  class UnaryGate < Token
    def stored_state
      @stored_state ||= ""
    end
    def char_accepted ch
      stored_state << ch
      "NOT".match("^#{stored_state}")
    end
  end
  class BinaryGate < Token
    GATES = %w(AND OR)
    def stored_state
      @stored_state ||= ""
    end
    def possible_gates
      @possible_gates ||= GATES.dup
    end
    def char_accepted ch
      stored_state << ch
      possible_gates.keep_if do |gate|
        gate.match("^#{stored_state}")
      end
      !possible_gates.empty?
    end
  end
  class ShiftGate < Token
    GATES = %w(LSHIFT RSHIFT)
    def stored_state
      @stored_state ||= ""
    end
    def possible_gates
      @possible_gates ||= GATES.dup
    end
    def char_accepted ch
      stored_state << ch
      possible_gates.keep_if do |gate|
        gate.match("^#{stored_state}")
      end
      !possible_gates.empty?
    end
  end
  class Wire < Token
    def char_accepted ch
      ch.match(/[a-z]/)
    end
  end
  class Arrow < Token
    def stored_state
      @stored_state ||= ""
    end
    def char_accepted ch
      stored_state << ch
      "->".match("^#{stored_state}")
    end
  end

  def self.parse text
    line = 1
    position = 0
    tokens = []
    all_chars = text.chars.dup
    loop do
      options = (self.constants - [:Token]).map { |opt| const_get(opt).new(line, position) }
      loop do
        ch = all_chars.shift
        if ch == "#"
          loop do
            break if all_chars.shift == "\n"
          end
          next
        end
        position += 1
        if ch == "\n"
          position = 0
          line += 1
        end
        if ch && ch.match(/\s/)
          if options.length == 1
            tokens << options[0]
            break
          elsif options.length > 1
            puts "I don't know what kind of token this is"
            puts options.inspect
            puts "#{line}:#{position}"
            puts (" "*(position-1)) + "^"
            puts tokens.inspect
            exit
          else
            next
          end
        end
        return tokens if ch.nil?

        options.keep_if do |token_type|
          token_type.add_char(ch)
        end

        if options.length == 0
          puts "Error at #{line}:#{position}"
          puts text.lines[line-1]
          puts ("."*(position-1)) + "^"
          puts tokens.inspect
          exit
        end
      end
    end
    return tokens
  end
end

module AST
  class Node
    def initialize tokens, children = []
      @tokens = tokens
      @children = children
    end
    def peek
      @tokens[0]
    end
    def take
      @tokens.shift
    end
    def expect klass
      if peek.is_a?(klass)
        take
      else
        puts "Expected #{klass}, found #{peek}"
        exit
      end
    end
    def add_child type
      @children << build_child(type)
    end
    def build_child type, children = []
      type.new(@tokens, children).build
    end
    def with_indent indent
      str = " "*indent + self.class.to_s + "\n"
      str += @children.map do |child|
        if child.respond_to?(:with_indent)
          child.with_indent(indent + 2)
        else
          (" " * (indent + 2)) + child.to_s + "\n"
        end
      end.join
      return str
    end
    def to_s
      with_indent(0)
    end
  end
  class Schematic < Node
    def statements
      @children
    end
    def build
      loop do
        @children << build_child(Statement)
        break if peek.nil?
      end
      return self
    end
  end
  class Statement < Node
    def expression
      @children[0]
    end
    def result
      @children[1]
    end
    def build
      add_child(Expression)
      expect(Parser::Arrow)
      add_child(Result)
      return self
    end
  end
  class Expression < Node
    def build
      case peek
      when Parser::Number
        value = expect(Parser::Number)
        case peek
        when Parser::BinaryGate
          build_child(BinaryExpression, [value])
        when Parser::Arrow
          build_child(SignalExpression, [value])
        else
          puts "Found unexpected #{peek} after #{value}"
          exit
        end
      when Parser::UnaryGate
        build_child(UnaryExpression)
      when Parser::Wire
        value = expect(Parser::Wire)
        case peek
        when Parser::BinaryGate, Parser::ShiftGate
          build_child(BinaryExpression, [value])
        when Parser::Arrow
          build_child(SignalExpression, [value])
        else
          puts "Found unexpected #{peek} after #{value}"
          exit
        end
      else
        puts "Found unexpected #{peek} beginning an expression"
        exit
      end
    end
  end
  class SignalExpression < Expression
    def value
      @children[0]
    end
    def build
      @children[0] ||= expect(Parser::Number)
      return self
    end
  end
  class UnaryExpression < Expression
    def operand
      @children[1]
    end
    def operator
      @children[0].spelling
    end
    def build
      @children << expect(Parser::UnaryGate)
      @children << expect(Parser::Wire)
      return self
    end
  end
  class BinaryExpression < Expression
    def build
      @children[0] ||= expect(Parser::Wire)
      case peek
      when Parser::BinaryGate
        build_child(ComboExpression, @children)
      when Parser::ShiftGate
        build_child(ShiftExpression, @children)
      else
        puts "Found #{peek} as the operator in a binary expression"
        exit
      end
    end
  end
  class ComboExpression < BinaryExpression
    def l_operand
      @children[0]
    end
    def r_operand
      @children[2]
    end
    def operator
      @children[1].spelling
    end
    def build
      @children << expect(Parser::BinaryGate)
      @children << expect(Parser::Wire)
      return self
    end
  end
  class ShiftExpression < BinaryExpression
    def l_operand
      @children[0]
    end
    def r_operand
      @children[2]
    end
    def operator
      @children[1].spelling
    end
    def build
      @children << expect(Parser::ShiftGate)
      @children << expect(Parser::Number)
      return self
    end
  end
  class Result < Node
    def name
      @children[0].spelling
    end
    def build
      @children << expect(Parser::Wire)
      return self
    end
  end
end

class Emulator
  class Gate
    attr_accessor :inputs, :output
    def to_u16 num
      raise ArgumentError unless num.instance_of?(Fixnum)
      15.downto(0).map { |i| num[i].to_s }.join.to_i(2)
    end
    def value
      to_u16(get_value)
    end

    def read item
      case item
      when Fixnum
        item
      when Wire
        item.value
      end
    end

    def l
      read @inputs[0]
    end
    alias :i :l

    def r
      read @inputs[1]
    end
  end
  class BinaryGate < Gate
    def initialize l, r
      @inputs = [l, r]
    end
  end
  class AndGate < BinaryGate
    def get_value
      l & r
    end
  end
  class OrGate < BinaryGate
    def get_value
      l | r
    end
  end
  class LshiftGate < BinaryGate
    def get_value
      l << r
    end
  end
  class RshiftGate < BinaryGate
    def get_value
      l >> r
    end
  end
  class UnaryGate < Gate
    def initialize r
      @inputs = [r]
    end
  end
  class IdentityGate < UnaryGate
    def get_value
      i
    end
  end
  class NotGate < UnaryGate
    def get_value
      ~i
    end
  end
  class Wire
    attr_accessor :source, :dest, :signal
    def value
      @signal ||= @source.value
    end
    def to_s
      "(#{self.class} #{@signal})"
    end
  end
  def initialize schematic
    @schematic = schematic
    @wires = {}
  end
  def get token
    case token
    when Parser::Number
      token.spelling.to_i
    when Parser::Wire
      get_wire(token.spelling)
    end
  end
  def get_wire name
    @wires[name] ||= Wire.new
  end
  def build
    @schematic.statements.each do |statement|
      expression = statement.expression
      result = get_wire(statement.result.name)
      gate =
        case expression
        when AST::SignalExpression
          wire = Wire.new
          case expression.value
          when Parser::Number
            wire.signal = expression.value.spelling.to_i
          when Parser::Wire
            wire.source = get_wire(expression.value.spelling)
          end
          IdentityGate.new wire
        when AST::ComboExpression, AST::ShiftExpression
          l = get(expression.l_operand)
          r = get(expression.r_operand)
          self.class.const_get(Unicode::capitalize(expression.operator.downcase) + "Gate").new l, r
        when AST::UnaryExpression
          operand = get(expression.operand)
          self.class.const_get(Unicode::capitalize(expression.operator.downcase) + "Gate").new operand
        else
          puts "Unknown expression #{expression.class}"
          exit
        end
      result.source = gate
      gate.output = result
    end
  end
  def display wires = nil
    ((wires.instance_of?(Array) && wires) || @wires.keys).map do |k|
      [k, @wires[k].value]
    end
  end
end

# parse into tokens
tokens = Parser.parse(File.read(filename))
# build ast/schematic
schematic = AST::Schematic.new(tokens).build
# emulate
emulator = Emulator.new(schematic)
emulator.build
wires =
  if ARGV.length > 1
    emulator.display(ARGV[1..-1])
  else
    emulator.display
  end
wires.each do |name, value|
  puts "#{name}: #{value}"
end
