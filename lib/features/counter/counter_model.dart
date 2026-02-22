class CounterModel {
  final int value;

  CounterModel({required this.value});

  CounterModel copyWith({int? value}) {
    return CounterModel(
      value: value ?? this.value,
    );
  }
}