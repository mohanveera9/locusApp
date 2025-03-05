import 'dart:math';
import 'package:flutter/material.dart';
import 'package:locus/Pages/Home/Explore/adminView.dart';
import 'package:locus/Pages/Home/Explore/newGroup.dart';
import 'package:locus/Pages/Home/Explore/userView.dart';
import 'package:locus/widgets/exploreContainer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class Explore extends StatefulWidget {
  const Explore({super.key});

  @override
  State<Explore> createState() => _ExploreState();
}

class _ExploreState extends State<Explore> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  // UI state variables.
  bool isOpen = false;
  bool isAdmin = true;
  bool isAccepted = false;
  bool filter = false;
  bool isSearch = false;
  bool isLoading = true;
  String searchQuery = '';
  List<String> selectedTags = [];
  List<Map<String, dynamic>> exploreList = [];

  // Current user location and distance threshold.
  double currentUserLat = 16.7930;
  double currentUserLong = 80.8225;
  double distanceThreshold = 10000.0; // e.g., 10 kilometers

  final FocusNode _focusNode = FocusNode();

  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300), // Faster animation
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _setLocation(); // Fetch the user's current location from their profile.
    setupRealtimeListeners(); // Note: Changed to plural to setup multiple listeners
    _fetchData();
    _focusNode.addListener(() {
      setState(() {
        isOpen = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Sets up realtime listeners for both community and profile tables.
  void setupRealtimeListeners() {
    // Listen for changes to the community table
    supabase
        .from('community')
        .stream(primaryKey: ['id']).listen((List<Map<String, dynamic>> data) {
      updateExploreList(data);
    });

    // Listen for changes to the current user's profile
    final userId = supabase.auth.currentUser!.id;
    supabase
        .from('profile')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .listen((List<Map<String, dynamic>> data) {
          if (data.isNotEmpty) {
            // Check if range has changed
            final newRange = double.parse(data[0]["range"].toString());
            if (newRange != distanceThreshold) {
              setState(() {
                // Update the distance threshold with the new range
                distanceThreshold = newRange;
                currentUserLat = data[0]["last_loc"]["lat"] as double;
                currentUserLong = data[0]["last_loc"]["long"] as double;
              });
              // Refresh data with the new range
              _fetchData();
            }
          }
        });
  }

  /// Retrieves the current user's location settings from their profile.
  Future<void> _setLocation() async {
    final userId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('profile')
        .select("last_loc, range")
        .eq("user_id", userId)
        .single();
    setState(() {
      currentUserLat = data["last_loc"]["lat"] as double;
      currentUserLong = data["last_loc"]["long"] as double;
      distanceThreshold = double.parse(data["range"].toString());
    });
  }

  /// Sets up a realtime listener on the 'community' table.
  void setupRealtimeListener() {
    supabase
        .from('community')
        .stream(primaryKey: ['id']).listen((List<Map<String, dynamic>> data) {
      updateExploreList(data);
    });
  }

  /// Fetches all community records.
  Future<void> _fetchData() async {
    // Ensure you retrieve the location field as well.
    final data = await supabase.from('community').select();
    updateExploreList(data);
    setState(() {
      isLoading = false;
    });
  }

  /// Calculates the distance (in meters) between two geographic coordinates
  /// using the Haversine formula.
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000; // Earth's radius in meters.
    final double dLat = (lat2 - lat1) * (pi / 180);
    final double dLon = (lon2 - lon1) * (pi / 180);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) *
            cos(lat2 * (pi / 180)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  /// Updates the explore list by filtering communities that are accepted,
  /// are not the user's own group, and are within the specified distance.
  /// Fetch last message for a community
  Future<String?> fetchLastMessage(String comId) async {
    final fetchedMessages = await supabase
        .from("community_messages")
        .select("message, created_at")
        .eq("com_id", comId)
        .order("created_at", ascending: false)
        .limit(1)
        .maybeSingle();

    return fetchedMessages?['message'];
  }

  /// Updates explore list with last message included
  void updateExploreList(List<Map<String, dynamic>> data) async {
    final userId = supabase.auth.currentUser!.id;
    final prof = await supabase
        .from("profile")
        .select("com_id")
        .eq("user_id", userId)
        .maybeSingle();

    List<Map<String, dynamic>> updatedList = [];

    for (var item in data) {
      if (!(item['accepted'] == true && item['com_id'] != prof?['com_id'])) {
        continue;
      }

      if (item['location'] == null) continue;
      final loc = item['location'];
      final double communityLat = loc['lat'] is num
          ? loc['lat'].toDouble()
          : double.tryParse(loc['lat'].toString()) ?? 0;
      final double communityLong = loc['long'] is num
          ? loc['long'].toDouble()
          : double.tryParse(loc['long'].toString()) ?? 0;

      final double distance = calculateDistance(
          currentUserLat, currentUserLong, communityLat, communityLong);

      if (distance > distanceThreshold) continue;

      // Fetch last message asynchronously
      final lastMessage = await fetchLastMessage(item['com_id']);

      updatedList.add({
        'id': item['id'].toString(),
        'name': item['title'],
        'description': item['desc'],
        'last_message': lastMessage,
        'created_at': item['created_at'],
        'tag': item['tags'],
        'img': 'assets/img/mohan.jpg',
        'com_id': item['com_id']
      });
    }

    setState(() {
      exploreList = updatedList;
    });
  }

  /// Further filters the list based on search query and selected tags.
  List<Map<String, dynamic>> getFilteredExploreList() {
    return exploreList.where((item) {
      final matchesSearch =
          item['name'].toLowerCase().contains(searchQuery.toLowerCase());
      final matchesTag =
          selectedTags.isEmpty || selectedTags.contains(item['tag']);
      return matchesSearch && matchesTag;
    }).toList();
  }

  void _showBottomSheet() {
    _controller.forward(from: 0); // Start animation

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            double height = _animation.value *
                MediaQuery.of(context).size.height *
                0.9; // Expanding effect

            return Container(
              height: height,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Center(child: Newgroup()),
            );
          },
        );
      },
    ).whenComplete(() => _controller.reverse());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        setState(() {
          isOpen = false;
        });
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Theme.of(context).colorScheme.primary,
          title: isSearch
              ? TextField(
                  focusNode: _focusNode,
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value;
                    });
                  },
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 17),
                  decoration: const InputDecoration(
                    hintText: 'Search...',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                )
              : const Padding(
                  padding: EdgeInsets.only(left: 20.0),
                  child: Text(
                    'Explore',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      fontFamily: 'Electrolize',
                    ),
                  ),
                ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 20.0),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    isSearch = !isSearch; // Toggle search mode
                    if (!isSearch) {
                      searchQuery =
                          ''; // Clear search query when closing search
                    }
                  });
                },
                child: Icon(
                  isSearch ? Icons.close : Icons.search,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                        left: 20, right: 20, bottom: isOpen ? 0 : 80),
                    child: Column(
                      children: [
                        if (isAdmin && !isSearch)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            child: GestureDetector(
                              onTap: (isAdmin && isAccepted)
                                  ? () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (builder) =>
                                              const Adminview(),
                                        ),
                                      )
                                  : null,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(15),
                                  color: isAdmin
                                      ? (isAccepted
                                          ? Theme.of(context)
                                              .colorScheme
                                              .secondary
                                          : Colors.orange.shade700)
                                      : Colors.grey,
                                ),
                                padding: const EdgeInsets.all(15.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isAdmin
                                          ? (isAccepted
                                              ? 'Your Group'
                                              : 'Your Group is not accepted yet')
                                          : 'Not an Admin',
                                      style: const TextStyle(
                                          color: Colors.black, fontSize: 15),
                                    ),
                                    if (isAccepted)
                                      const Icon(Icons.arrow_forward,
                                          color: Colors.black),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ListView.builder(
                              itemCount: getFilteredExploreList().length,
                              itemBuilder: (context, index) {
                                final list = getFilteredExploreList()[index];
                                final String displayText = (list['last_message']
                                        as String?) ??
                                    "${(list['description'] as String?) ?? 'No description available'} • ${timeago.format(DateTime.tryParse(list['created_at'] ?? '') ?? DateTime.now())}";

                                return GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(
                                        MaterialPageRoute(builder: (context) {
                                      return Userview(
                                        id: list['com_id'],
                                        name: list['name'],
                                      );
                                    }));
                                  },
                                  child: Explorecontainer(
                                    name: list['name'],
                                    description: displayText,
                                    img: list['img'],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isSearch)
                    Positioned(
                      bottom: 100,
                      right: 30,
                      child: GestureDetector(
                        onTap: _showBottomSheet,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class CircleClipper extends CustomClipper<Rect> {
  final double radius;

  CircleClipper(this.radius);

  @override
  Rect getClip(Size size) {
    return Rect.fromCircle(
        center: size.bottomCenter(Offset.zero), radius: radius);
  }

  @override
  bool shouldReclip(CircleClipper oldClipper) {
    return oldClipper.radius != radius;
  }
}
