module RubyZero::Core
    class Tensor
        attr_reader :shape, :dtype
        attr_accessor :grad_function, :grad_tensor, :requires_grad, :data, :device
        # Initialize tensor with same shape.
        # @param [Array<Object>|Tensor|Numeric] data
        # @param [Shape] shape
        # @param [Datatypes::DType] dtype
        # @param [Device] device
        def initialize(data=[], shape:nil, dtype: nil, device:Device.new(:numo)) # TODO: Refactor this method.
            shape ||= Shape.new()
            if data
                if data.is_a?(Array)
                    data_arr = Numo::NArray[*data]
                    predicted_type = DataTypes::Float64
                    if data.flatten[0].is_a?(Integer)
                        predicted_type = DataTypes::Int64
                    elsif data.flatten[0].is_a?(Float)
                        predicted_type = DataTypes::Float64
                    elsif data.flatten[0].is_a?(Complex)
                        predicted_type = DataTypes::Complex128
                    else
                        predicted_type = DataTypes::RObject
                    end
                    @dtype ||= predicted_type
                    data = @dtype.get_dtype_on_device(device).cast(data_arr)
                    @shape = shape || Shape.new(*data.shape)
                elsif data.is_a?(Numeric)
                    predicted_type = DataTypes::RObject
                    if data.is_a?(Integer)
                        predicted_type = DataTypes::Int64
                    elsif data.is_a?(Float)
                        predicted_type = DataTypes::Float64
                    elsif data.is_a?(Complex)
                        predicted_type = DataTypes::Complex128
                    end
                    xmo_type = predicted_type.get_dtype_on_device(device)
                    data = xmo_type[data]
                    device = device
                elsif data.is_a?(Numo::NArray)
                    @dtype ||= DataTypes::from_numo_dtype(data.class)
                elsif data.is_a?(Tensor)
                    data = data.data
                else
                    raise TypeError, "#{data.class} is cannot convert to tensor. data must be Array or Numo::NArray."
                end
                @device = device
                @data = data
                @shape ||= Shape.new(*data.shape.to_a)
                @dtype ||= DataTypes::from_numo_dtype(data.class)
            else
                @device = device
                @shape = shape
                @dtype ||= DataTypes::RObject
                @data = @dtype.get_dtype_on_device(@device).zeros(*@shape.to_a)
            end
            @grad_function = nil
            @grad_tensor = nil
            @requires_grad = false
            return Functions::Constant.new.call(self)
        end

        def init_grad_tensor
            @grad_tensor = nil
        end

        def shape
            old = @shape
            @shape = Shape.new(*self.data.shape.to_a)
            apply_shape old
            @shape
        end
        # Execute gradient function.
        # @return [RubyZero::Core::Tensor]
        def backward()
            p "BACKWARD #{@grad_function.class}"
            @grad_tensor ||= ones_like()
            if @grad_function
                grad_result = @grad_function.backward(@grad_tensor)
                self.grad_function.input.each_with_index do |t, i|
                    if t.requires_grad
                        p "BW GR IN ITER"

                        gi = grad_result[i]
                        p gi
                        raise "wuat" unless gi
                        t.add_grad gi
                        t.backward()
                    end
                end
            end
            return self
        end

        # Add gradient to self.
        # @param [RubyZero::Core::Tensor] grad_t
        # @return [RubyZero::Core::Tensor]
        def add_grad(grad_t)
            p "CALLED ADDGRAD"
            if @grad_tensor
                @grad_tensor += grad_t
            else
                @grad_tensor = grad_t
            end
        end

        # @retrun [String]
        def inspect
            numo_inspect = @data.inspect.split("\n")[1..nil].join("\n")
            return "#{dtype}#shape=#{shape.to_a}\n#{numo_inspect}\ngrad_function=#{@grad_function.class}"
        end

        # @return [Integer]
        def ndim
            return self.shape.ndim
        end

        # @param [Datatypes::DType] dtype
        def cast_to!(dtype)
            @data = dtype.get_dtype_on_device(@device).cast(@data)
            if @grad_tensor and @grad_tensor.dtype != dtype and @grad_tensor != self
                @grad_tensor.cast_to(dtype)
            end
            return self
        end

        # @param [Datatypes::DType] dtype
        def cast_to(dtype)
            return dup.cast_to!(dtype)
        end

        # initialize RubyZero::Core::Tensor[1, 2, 3... ] style.
        # @param [Array<Object>] data
        # @return [RubyZero::Core::Tensor]
        def self.[](*data)
            Tensor.new(data)
        end

        # @return [Array<Object>]
        def to_a
            return self.data.to_a
        end

        # Initialize zeros tensor.
        # @param [Shape|Array<Integer>] shape
        # @param [Datatypes::DType] dtype
        # @option options [Device] :device
        # @return [RubyZero::Core::Tensor]
        def self.zeros(shape, dtype, device:Device.new(:numo))
            data = dtype.get_dtype_on_device(device).zeros(*shape.to_a)
            t = new(data, shape: shape, dtype: dtype)
            return t
        end
        # Initialize ones tensor.
        # @param [Shape|Array<Integer>] shape
        # @param [Datatypes::DType] dtype
        # @option options [Device] :device
        # @return [RubyZero::Core::Tensor]
        def self.ones(shape, dtype, device:Device.new(:numo))
            data = dtype.get_dtype_on_device(device).ones(*shape.to_a)
            t = new(data, shape: shape, dtype: dtype)
            return t
        end

        # Initialize tensor with other tensor's shape, dtype, and device. witch data is zeros.
        # @param [RubyZero::Core::Tensor] tensor
        # @return [RubyZero::Core::Tensor]
        def self.zeros_like(tensor)
            shape, dtype, device = tensor.shape, tensor.dtype, tensor.device
            data = dtype.get_dtype_on_device(device).zeros(*shape.to_a)
            t = new(data, shape: shape, dtype: dtype, device: device)
            return t
        end
        # Initialize tensor with other tensor's shape, dtype, and device. witch data is ones.
        # @param [RubyZero::Core::Tensor] tensor
        # @return [RubyZero::Core::Tensor]
        def self.ones_like(tensor)
            shape, dtype, device = tensor.shape, tensor.dtype, tensor.device
            data = dtype.get_dtype_on_device(device).ones(*shape.to_a)
            t = new(data, shape: shape, dtype: dtype, device: device)
            return t
        end

        # Initialize tensor randomly.
        # @param [Shape|Array<Integer>] shape
        # @return [RubyZero::Core::Tensor]
        def self.rand(shape, dtype, device:Device.new(:numo))
            if shape[0].is_a?(Shape)
                shape = shape[0].to_a
            end
            data = dtype.get_dtype_on_device(device).rand(*shape)
            t = new(data, shape: shape, dtype: dtype, device: device)
            return t
        end

        # Initialize tensor with other tensor's shape, dtype, and device. witch data is random.
        # @param [RubyZero::Core::Tensor] other
        # @return [RubyZero::Core::Tensor]
        def self.rand_like(other)
            shape, dtype, device = other.shape, other.dtype, other.device
            data = dtype.get_dtype_on_device(device).rand(*shape)
            t = new(data, shape: shape, dtype: dtype, device: device)
            return t
        end

        # Initialize tensor normal random value.
        # @param [Shape|Array<Integer>] shape
        # @return [RubyZero::Core::Tensor]
        def self.rand_norm(shape, dtype, device:Device.new(:numo))
            if shape[0].is_a?(Shape)
                shape = shape[0].to_a
            end
            data = dtype.get_dtype_on_device(device).rand_norm(*shape)
            t = new(data, shape: shape, dtype: dtype, device: device)
            return t
        end

        # Initialize tensor with other tensor's shape, dtype, and device. witch data is random normal value.
        # @param [RubyZero::Core::Tensor] other
        # @return [RubyZero::Core::Tensor]
        def self.rand_norm_like(other)
            shape, dtype, device = other.shape, other.dtype, other.device
            data = dtype.get_dtype_on_device(device).rand_norm(*shape)
            t = new(data, shape: shape, dtype: dtype, device: device)
            return t
        end
        
        # Initialize tensor with same shape, same dtype, and same device. witch data is zeros.
        # @return [RubyZero::Core::Tensor]
        def zeros_like
            return self.class.zeros_like(self)
        end

        # Initialize tensor with same shape, same dtype, and same device. witch data is ones.
        # @return [RubyZero::Core::Tensor]
        def ones_like
            return self.class.ones_like(self)
        end

        # Detach tensor from calculation graph.
        # @return [Tensor]
        def detach
            self.grad_function = nil
            return self
        end
    end
end

module TensorInitializer
    Tensor = RubyZero::Core::Tensor
    FloatTensor = RubyZero::Core::DataTypes::Float32
    IntTensor = RubyZero::Core::DataTypes::Int32
    LongTensor = RubyZero::Core::DataTypes::Int64
    DoubleTensor = RubyZero::Core::DataTypes::Float64
end

module RubyZero
    include TensorInitializer
end