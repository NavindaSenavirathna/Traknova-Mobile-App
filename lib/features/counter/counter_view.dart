// import 'package:flutter/material.dart';
// import '../../core/views/base_view.dart';
// import 'counter_view_model.dart';

// class CounterView extends StatelessWidget {
//   const CounterView({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return BaseView<CounterViewModel>(
//       viewModel: CounterViewModel(),
//       builder: (context, model, child) => Scaffold(
//         appBar: AppBar(
//           title: const Text('MVVM Counter Example'),
//         ),
//         body: Center(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               const Text(
//                 'You have pushed the button this many times:',
//               ),
//               Text(
//                 '${model.count}',
//                 style: Theme.of(context).textTheme.headlineMedium,
//               ),
//             ],
//           ),
//         ),
//         floatingActionButton: Column(
//           mainAxisAlignment: MainAxisAlignment.end,
//           children: [
//             FloatingActionButton(
//               onPressed: model.increment,
//               tooltip: 'Increment',
//               child: const Icon(Icons.add),
//             ),
//             const SizedBox(height: 8),
//             FloatingActionButton(
//               onPressed: model.decrement,
//               tooltip: 'Decrement',
//               child: const Icon(Icons.remove),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }