// import 'package:flutter/material.dart';
// import 'package:vibeflow/services/audio_player_manager.dart';

// class AudioGovernanceDebugScreen extends StatefulWidget {
//   final AudioPlayerManager? audioManager;

//   const AudioGovernanceDebugScreen({super.key, this.audioManager});

//   @override
//   State<AudioGovernanceDebugScreen> createState() =>
//       _AudioGovernanceDebugScreenState();
// }

// class _AudioGovernanceDebugScreenState
//     extends State<AudioGovernanceDebugScreen> {
//   @override
//   void initState() {
//     super.initState();
//     // Refresh every second to show live updates
//     Future.doWhile(() async {
//       await Future.delayed(const Duration(seconds: 1));
//       if (mounted) {
//         setState(() {});
//         return true;
//       }
//       return false;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (widget.audioManager == null) {
//       return Scaffold(
//         backgroundColor: const Color(0xFF0A0E27),
//         appBar: AppBar(
//           backgroundColor: const Color(0xFF1A1F3A),
//           elevation: 0,
//           title: const Text(
//             'Audio Governance Debug',
//             style: TextStyle(
//               fontFamily: 'Cabin',
//               fontSize: 20,
//               fontWeight: FontWeight.w600,
//               color: Colors.white,
//             ),
//           ),
//           leading: IconButton(
//             icon: const Icon(Icons.arrow_back, color: Colors.white),
//             onPressed: () => Navigator.pop(context),
//           ),
//         ),
//         body: const Center(
//           child: Text(
//             'Audio Manager not available',
//             style: TextStyle(
//               fontFamily: 'Cabin',
//               fontSize: 16,
//               color: Color(0xFF94A3B8),
//             ),
//           ),
//         ),
//       );
//     }

//     final governance = widget.audioManager!.currentGovernanceContext;
//     final currentSong = widget.audioManager!.currentSong;
//     final isPlaying = widget.audioManager!.isPlaying;

//     return Scaffold(
//       backgroundColor: const Color(0xFF0A0E27),
//       appBar: AppBar(
//         backgroundColor: const Color(0xFF1A1F3A),
//         elevation: 0,
//         title: const Text(
//           'Audio Governance Debug',
//           style: TextStyle(
//             fontFamily: 'Cabin',
//             fontSize: 20,
//             fontWeight: FontWeight.w600,
//             color: Colors.white,
//           ),
//         ),
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back, color: Colors.white),
//           onPressed: () => Navigator.pop(context),
//         ),
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Current Operation
//             _buildSection(
//               title: 'Current Operation',
//               icon: Icons.play_circle_filled,
//               iconColor: const Color(0xFF6366F1),
//               child: governance != null
//                   ? Column(
//                       children: [
//                         _buildInfoRow('Operation', governance.operation.name),
//                         _buildInfoRow('Priority', '${governance.priority}'),
//                         _buildInfoRow('Source', governance.source.name),
//                         _buildInfoRow('Video ID', governance.videoId),
//                         _buildInfoRow(
//                           'Timestamp',
//                           _formatTime(governance.timestamp),
//                         ),
//                         _buildInfoRow(
//                           'User Initiated',
//                           governance.isUserInitiated ? 'Yes' : 'No',
//                         ),
//                       ],
//                     )
//                   : _buildEmptyState('No active operation'),
//             ),

//             const SizedBox(height: 20),

//             // Current Playback
//             _buildSection(
//               title: 'Current Playback',
//               icon: Icons.music_note,
//               iconColor: const Color(0xFF8B5CF6),
//               child: currentSong != null
//                   ? Column(
//                       children: [
//                         _buildInfoRow('Song', currentSong.title),
//                         _buildInfoRow('Artist', currentSong.artists),
//                         _buildInfoRow('Video ID', currentSong.videoId),
//                         _buildInfoRow(
//                           'Status',
//                           isPlaying ? 'Playing' : 'Paused',
//                         ),
//                       ],
//                     )
//                   : _buildEmptyState('No song loaded'),
//             ),

//             const SizedBox(height: 20),

//             // Radio State
//             _buildSection(
//               title: 'Radio State',
//               icon: Icons.radio,
//               iconColor: const Color(0xFFEC4899),
//               child: Column(
//                 children: [
//                   _buildInfoRow(
//                     'Active Source',
//                     widget.audioManager!.activeRadioSource ?? 'None',
//                   ),
//                   _buildInfoRow(
//                     'Radio Queue',
//                     '${widget.audioManager!.radioQueue.length} songs',
//                   ),
//                   _buildInfoRow(
//                     'Radio Index',
//                     '${widget.audioManager!.radioQueueIndex}',
//                   ),
//                   if (widget.audioManager!.radioQueue.isNotEmpty)
//                     _buildInfoRow(
//                       'Next Radio Song',
//                       widget.audioManager!.radioQueueIndex <
//                               widget.audioManager!.radioQueue.length - 1
//                           ? widget
//                                 .audioManager!
//                                 .radioQueue[widget
//                                         .audioManager!
//                                         .radioQueueIndex +
//                                     1]
//                                 .title
//                           : 'End of queue',
//                     ),
//                 ],
//               ),
//             ),

//             const SizedBox(height: 20),

//             // Queue State
//             _buildSection(
//               title: 'Queue State',
//               icon: Icons.queue_music,
//               iconColor: const Color(0xFF10B981),
//               child: Column(
//                 children: [
//                   _buildInfoRow(
//                     'Manual Queue',
//                     '${widget.audioManager!.manualQueue.length} songs',
//                   ),
//                   _buildInfoRow(
//                     'Queue Index',
//                     '${widget.audioManager!.queueIndex}',
//                   ),
//                   if (widget.audioManager!.manualQueue.isNotEmpty)
//                     _buildInfoRow(
//                       'Next Queue Song',
//                       widget.audioManager!.queueIndex <
//                               widget.audioManager!.manualQueue.length - 1
//                           ? widget
//                                 .audioManager!
//                                 .manualQueue[widget.audioManager!.queueIndex +
//                                     1]
//                                 .title
//                           : 'End of queue',
//                     ),
//                 ],
//               ),
//             ),

//             const SizedBox(height: 20),

//             // Autoplay State
//             _buildSection(
//               title: 'Autoplay State',
//               icon: Icons.auto_awesome,
//               iconColor: const Color(0xFFF59E0B),
//               child: Column(
//                 children: [
//                   _buildInfoRow(
//                     'Enabled',
//                     widget.audioManager!.autoplayEnabled ? 'Yes' : 'No',
//                   ),
//                   _buildInfoRow('Status', _getAutoplayStatus()),
//                 ],
//               ),
//             ),

//             const SizedBox(height: 20),

//             // Next Decision
//             _buildSection(
//               title: 'Next Decision (Skip Next)',
//               icon: Icons.skip_next,
//               iconColor: const Color(0xFF3B82F6),
//               child: Column(
//                 children: [
//                   _buildInfoRow('Action', _predictNextAction()),
//                   _buildInfoRow('Reason', _getNextActionReason()),
//                   _buildInfoRow('Confidence', 'HIGH'),
//                 ],
//               ),
//             ),

//             const SizedBox(height: 20),

//             // Priority Legend
//             _buildSection(
//               title: 'Priority Legend',
//               icon: Icons.info_outline,
//               iconColor: const Color(0xFF64748B),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   _buildPriorityItem(1, 'USER_PLAY, USER_NAVIGATE'),
//                   _buildPriorityItem(2, 'ERROR_RECOVERY, QUEUE_SYNC'),
//                   _buildPriorityItem(3, 'AUTOPLAY'),
//                   _buildPriorityItem(5, 'BACKGROUND_FETCH'),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildSection({
//     required String title,
//     required IconData icon,
//     required Color iconColor,
//     required Widget child,
//   }) {
//     return Container(
//       decoration: BoxDecoration(
//         color: const Color(0xFF1A1F3A),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: const Color(0xFF2D3348), width: 1),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Header
//           Container(
//             padding: const EdgeInsets.all(16),
//             decoration: BoxDecoration(
//               color: const Color(0xFF0F1629),
//               borderRadius: const BorderRadius.only(
//                 topLeft: Radius.circular(16),
//                 topRight: Radius.circular(16),
//               ),
//             ),
//             child: Row(
//               children: [
//                 Container(
//                   padding: const EdgeInsets.all(8),
//                   decoration: BoxDecoration(
//                     color: iconColor.withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: Icon(icon, color: iconColor, size: 20),
//                 ),
//                 const SizedBox(width: 12),
//                 Text(
//                   title,
//                   style: const TextStyle(
//                     fontFamily: 'Cabin',
//                     fontSize: 16,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.white,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           // Content
//           Padding(padding: const EdgeInsets.all(16), child: child),
//         ],
//       ),
//     );
//   }

//   Widget _buildInfoRow(String label, String value) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 12),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Expanded(
//             flex: 2,
//             child: Text(
//               label,
//               style: const TextStyle(
//                 fontFamily: 'Cabin',
//                 fontSize: 14,
//                 color: Color(0xFF94A3B8),
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ),
//           const SizedBox(width: 16),
//           Expanded(
//             flex: 3,
//             child: Text(
//               value,
//               style: const TextStyle(
//                 fontFamily: 'Cabin',
//                 fontSize: 14,
//                 color: Colors.white,
//                 fontWeight: FontWeight.w600,
//               ),
//               textAlign: TextAlign.right,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildEmptyState(String message) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.symmetric(vertical: 16),
//         child: Text(
//           message,
//           style: const TextStyle(
//             fontFamily: 'Cabin',
//             fontSize: 14,
//             color: Color(0xFF64748B),
//             fontStyle: FontStyle.italic,
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildPriorityItem(int priority, String operations) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 8),
//       child: Row(
//         children: [
//           Container(
//             width: 32,
//             height: 32,
//             decoration: BoxDecoration(
//               color: _getPriorityColor(priority).withOpacity(0.1),
//               borderRadius: BorderRadius.circular(8),
//             ),
//             child: Center(
//               child: Text(
//                 '$priority',
//                 style: TextStyle(
//                   fontFamily: 'Cabin',
//                   fontSize: 14,
//                   fontWeight: FontWeight.bold,
//                   color: _getPriorityColor(priority),
//                 ),
//               ),
//             ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Text(
//               operations,
//               style: const TextStyle(
//                 fontFamily: 'Cabin',
//                 fontSize: 13,
//                 color: Color(0xFF94A3B8),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Color _getPriorityColor(int priority) {
//     switch (priority) {
//       case 1:
//         return const Color(0xFFEF4444);
//       case 2:
//         return const Color(0xFFF59E0B);
//       case 3:
//         return const Color(0xFF3B82F6);
//       default:
//         return const Color(0xFF64748B);
//     }
//   }

//   String _formatTime(DateTime time) {
//     return '${time.hour.toString().padLeft(2, '0')}:'
//         '${time.minute.toString().padLeft(2, '0')}:'
//         '${time.second.toString().padLeft(2, '0')}';
//   }

//   String _getAutoplayStatus() {
//     if (!widget.audioManager!.autoplayEnabled) {
//       return 'Disabled';
//     }
//     if (widget.audioManager!.isPlaying) {
//       return 'Active (playing)';
//     }
//     return 'Waiting (idle timer may trigger)';
//   }

//   String _predictNextAction() {
//     final manualQueue = widget.audioManager!.manualQueue;
//     final queueIndex = widget.audioManager!.queueIndex;
//     final radioQueue = widget.audioManager!.radioQueue;
//     final radioIndex = widget.audioManager!.radioQueueIndex;

//     // Check manual queue
//     if (manualQueue.isNotEmpty && queueIndex < manualQueue.length - 1) {
//       return 'Play from Manual Queue';
//     }

//     // Check radio queue
//     if (radioQueue.isNotEmpty && radioIndex < radioQueue.length - 1) {
//       return 'Play from Radio Queue';
//     }

//     // Load new radio
//     if (widget.audioManager!.currentSong != null) {
//       return 'Load New Radio & Play';
//     }

//     return 'No Action Available';
//   }

//   String _getNextActionReason() {
//     final manualQueue = widget.audioManager!.manualQueue;
//     final queueIndex = widget.audioManager!.queueIndex;
//     final radioQueue = widget.audioManager!.radioQueue;
//     final radioIndex = widget.audioManager!.radioQueueIndex;

//     if (manualQueue.isNotEmpty && queueIndex < manualQueue.length - 1) {
//       return 'Manual queue has ${manualQueue.length - queueIndex - 1} songs remaining';
//     }

//     if (radioQueue.isNotEmpty && radioIndex < radioQueue.length - 1) {
//       return 'Radio queue has ${radioQueue.length - radioIndex - 1} songs remaining';
//     }

//     if (widget.audioManager!.currentSong != null) {
//       return 'Will load radio for current song and play first track';
//     }

//     return 'No current song or queues available';
//   }
// }
