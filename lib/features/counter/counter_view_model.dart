import '../../core/viewmodels/base_view_model.dart';
import 'counter_model.dart';

class CounterViewModel extends BaseViewModel {
  CounterModel _counter = CounterModel(value: 0);
  
  int get count => _counter.value;

  void increment() {
    _counter = _counter.copyWith(value: _counter.value + 1);
    notifyListeners();
  }

  void decrement() {
    _counter = _counter.copyWith(value: _counter.value - 1);
    notifyListeners();
  }
}