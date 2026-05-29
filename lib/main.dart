import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const SmartPostureApp());
}

//////////////// TRACKER //////////////////

class PostureTracker {
  static final PostureTracker instance = PostureTracker._();
  PostureTracker._();

  int goodTime = 0;
  int totalTime = 0;
  int badEvents = 0;

  String posture = "DISCONNECTED";
  String lastPosture = "GOOD";

  bool isConnected = false;

  Timer? timer;
  String todayKey = "";

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    todayKey = DateTime.now().toString().substring(0, 10);

    goodTime = prefs.getInt("good_$todayKey") ?? 0;
    totalTime = prefs.getInt("total_$todayKey") ?? 0;
    badEvents = prefs.getInt("bad_$todayKey") ?? 0;

    startTimer();
  }

  void startTimer() {
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 1), (_) async {

      if (!isConnected) return; // 🔥 STOP when disconnected

      totalTime++;

      if (posture == "GOOD") goodTime++;

      final prefs = await SharedPreferences.getInstance();
      prefs.setInt("good_$todayKey", goodTime);
      prefs.setInt("total_$todayKey", totalTime);
      prefs.setInt("bad_$todayKey", badEvents);
    });
  }

  void updatePosture(String newPosture) {
    posture = newPosture;

    if (lastPosture == "GOOD" && newPosture == "SLOUCH") {
      badEvents++;
    }

    lastPosture = newPosture;
  }
}

//////////////// BLE //////////////////

class BleManager {
  static final BleManager instance = BleManager._();
  BleManager._();

  final String mac = "E0:8C:FE:58:DE:9E";

  BluetoothDevice? device;

  Future<void> start() async {
    while (true) {
      try {
        device = BluetoothDevice.fromId(mac);

        print("Trying to connect...");

        await device!.connect(timeout: const Duration(seconds: 10));

        print("Connected!");

        // 🔥 LISTEN REAL CONNECTION STATE
        device!.connectionState.listen((state) {
          if (state == BluetoothConnectionState.connected) {
            PostureTracker.instance.isConnected = true;
          } else {
            PostureTracker.instance.isConnected = false;
            PostureTracker.instance.posture = "DISCONNECTED";
          }
        });

        await Future.delayed(const Duration(seconds: 2));

        var services = await device!.discoverServices();

        for (var s in services) {
          for (var c in s.characteristics) {
            if (c.properties.notify) {

              await c.setNotifyValue(true);

              c.onValueReceived.listen((value) {
                String data = String.fromCharCodes(value);
                var p = data.split(",");

                if (p.length == 3) {
                  PostureTracker.instance.updatePosture(p[0]);
                }
              });

              return;
            }
          }
        }

      } catch (e) {
        print("Connection failed → retrying...");
        PostureTracker.instance.isConnected = false;
        PostureTracker.instance.posture = "DISCONNECTED";

        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }
}

////////////////////////////////////////////////

class SmartPostureApp extends StatelessWidget {
  const SmartPostureApp({super.key});

  @override
  Widget build(BuildContext context) {
    PostureTracker.instance.init();
    BleManager.instance.start();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

//////////////// HOME //////////////////

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  final screens = [
    const DashboardScreen(),
    const StatsScreen(),
    const SettingsScreen()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Stats"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
        ],
      ),
    );
  }
}

//////////////// DASHBOARD //////////////////

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  String format(int s) {
    int h = s ~/ 3600;
    int m = (s % 3600) ~/ 60;
    int sec = s % 60;
    return "${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}";
  }

  @override
  Widget build(BuildContext context) {

    var t = PostureTracker.instance;

    return Scaffold(
      appBar: AppBar(title: const Text("Smart Posture")),
      body: StreamBuilder(
        stream: Stream.periodic(const Duration(seconds: 1)),
        builder: (_, __) {

          double score = t.totalTime == 0 ? 0 : (t.goodTime / t.totalTime) * 100;

          return Column(
            children: [

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.circle,
                      size: 12,
                      color: t.isConnected ? Colors.green : Colors.red),
                  const SizedBox(width: 8),
                  Text(t.isConnected ? "Connected" : "Disconnected"),
                ],
              ),

              const SizedBox(height: 20),

              Text("Posture: ${t.posture}",
                  style: TextStyle(
                    fontSize: 22,
                    color: t.posture == "GOOD"
                        ? Colors.green
                        : t.posture == "SLOUCH"
                            ? Colors.orange
                            : Colors.red,
                  )),

              const SizedBox(height: 20),

              Text("Score: ${score.toStringAsFixed(1)}%",
                  style: const TextStyle(fontSize: 28)),

              const SizedBox(height: 20),

              Card(
                margin: const EdgeInsets.all(20),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      row("Good Time", format(t.goodTime)),
                      row("Total Time", format(t.totalTime)),
                      row("Bad Events", "${t.badEvents}"),
                    ],
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }

  Widget row(String a, String b) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(a), Text(b)],
      ),
    );
  }
}

//////////////// STATS //////////////////

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {

  List<double> total = List.filled(7, 0);
  List<double> bad = List.filled(7, 0);

  final days = ["Thu","Fri","Sat","Sun","Mon","Tue","Today"];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    for (int i = 0; i < 7; i++) {
      var day = DateTime.now().subtract(Duration(days: 6 - i));
      String key = day.toString().substring(0,10);

      double t = (prefs.getInt("total_$key") ?? 0).toDouble();
      double g = (prefs.getInt("good_$key") ?? 0).toDouble();

      total[i] = t / 60;
      bad[i] = (t - g) / 60;
    }

    setState(() {});
  }

  String format(double m) {
    int h = m ~/ 60;
    int min = (m % 60).toInt();
    return "${h.toString().padLeft(2,'0')}h ${min.toString().padLeft(2,'0')}m";
  }

  BarChartGroupData bar(int x, double y, Color c1, Color c2) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          width: 18,
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(colors: [c1, c2]),
        )
      ],
    );
  }

  Widget chart(List<double> data, Color c1, Color c2) {
    return BarChart(
      BarChartData(
        barGroups: List.generate(7, (i) => bar(i, data[i], c1, c2)),
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),

        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), // removed Y axis
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Text(days[v.toInt()]),
            ),
          ),
        ),

        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.black87,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (g, gi, rod, ri) {
              return BarTooltipItem(
                format(rod.toY),
                const TextStyle(color: Colors.white),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("Weekly Analysis")),
      body: StreamBuilder(
        stream: Stream.periodic(const Duration(seconds: 2)),
        builder: (_, __) {

          load();

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text("Total Sitting Time"),
                SizedBox(height: 200, child: chart(total, Colors.blue, Colors.cyan)),
                const SizedBox(height: 30),
                const Text("Bad Posture Time"),
                SizedBox(height: 200, child: chart(bad, Colors.orange, Colors.red)),
              ],
            ),
          );
        },
      ),
    );
  }
}

//////////////// SETTINGS //////////////////

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text("Settings")),
    );
  }
}