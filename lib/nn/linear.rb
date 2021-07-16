require_relative "./nn.rb"

module RubyZero::NN
    class Linear < Module
        def initialize(input_size, output_size, bias:true)
            @weight = FloatTensor.rand_norm([input_size, output_size], mean:0, std:10)
            @weight.trainable = true
            if bias
                @bias = FloatTensor.rand_norm([output_size])
                @bias.trainable = true
            end
            super()
        end
        def forward(x)
            y = x.dot(@weight)
            if @bias
                y += @bias
            end
            return y
        end
    end
end