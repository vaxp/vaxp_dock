import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/dock_settings_service.dart';

class DockSettingsDialog extends StatefulWidget {
  final DockSettings initialSettings;
  final Function(DockSettings) onSave;
  final VoidCallback? onRestart;
  final bool isWindowMode;

  const DockSettingsDialog({
    super.key,
    required this.initialSettings,
    required this.onSave,
    this.isWindowMode = false,
    this.onRestart,
  });

  @override
  State<DockSettingsDialog> createState() => _DockSettingsDialogState();
}

class _DockSettingsDialogState extends State<DockSettingsDialog> {
  late DockSettings _settings;
  late Color _currentColor;
  late double _currentTransparency;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _currentColor = _settings.barColor;
    _currentTransparency = _settings.transparency;
  }

  Future<void> _pickBackgroundImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _settings = _settings.copyWith(
          backgroundImagePath: result.files.single.path,
        );
      });
    }
  }

  Future<void> _pickIconPackDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _settings = _settings.copyWith(iconPackPath: result);
      });
    }
  }

  Future<void> _pickIconForApp(String appName) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        final newMappings = Map<String, String>.from(_settings.iconMappings);
        newMappings[appName] = result.files.single.path!;
        _settings = _settings.copyWith(iconMappings: newMappings);
      });
    }
  }

  void _removeBackgroundImage() {
    setState(() {
      _settings = _settings.copyWith(backgroundImagePath: null);
    });
  }

  void _removeIconPack() {
    setState(() {
      _settings = _settings.copyWith(iconPackPath: null, iconMappings: {});
    });
  }

  void _removeIconMapping(String appName) {
    setState(() {
      final newMappings = Map<String, String>.from(_settings.iconMappings);
      newMappings.remove(appName);
      _settings = _settings.copyWith(iconMappings: newMappings);
    });
  }

  Widget _buildSettingsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bar Color
        _buildSectionTitle('Bar Color'),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _currentColor,
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Color',
                    style: TextStyle(color: Colors.grey[300]),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _currentColor.red.toDouble(),
                          min: 0,
                          max: 255,
                          label: 'Red: ${_currentColor.red}',
                          onChanged: (value) {
                            setState(() {
                              _currentColor = Color.fromARGB(
                                _currentColor.alpha,
                                value.toInt(),
                                _currentColor.green,
                                _currentColor.blue,
                              );
                              _settings = _settings.copyWith(
                                barColor: _currentColor,
                              );
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _currentColor.green.toDouble(),
                          min: 0,
                          max: 255,
                          label: 'Green: ${_currentColor.green}',
                          onChanged: (value) {
                            setState(() {
                              _currentColor = Color.fromARGB(
                                _currentColor.alpha,
                                _currentColor.red,
                                value.toInt(),
                                _currentColor.blue,
                              );
                              _settings = _settings.copyWith(
                                barColor: _currentColor,
                              );
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _currentColor.blue.toDouble(),
                          min: 0,
                          max: 255,
                          label: 'Blue: ${_currentColor.blue}',
                          onChanged: (value) {
                            setState(() {
                              _currentColor = Color.fromARGB(
                                _currentColor.alpha,
                                _currentColor.red,
                                _currentColor.green,
                                value.toInt(),
                              );
                              _settings = _settings.copyWith(
                                barColor: _currentColor,
                              );
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Transparency
        _buildSectionTitle('Transparency'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _currentTransparency,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                label: '${(_currentTransparency * 100).toStringAsFixed(0)}%',
                onChanged: (value) {
                  setState(() {
                    _currentTransparency = value;
                    _settings = _settings.copyWith(
                      transparency: value,
                    );
                  });
                },
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                '${(_currentTransparency * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: Colors.grey[300]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Background Image
        _buildSectionTitle('Background Image'),
        const SizedBox(height: 10),
        if (_settings.backgroundImagePath != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _settings.backgroundImagePath!,
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _removeBackgroundImage,
                    icon: const Icon(Icons.delete),
                    label: const Text('Remove'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                    ),
                  ),
                ],
              ),
            ],
          )
        else
          ElevatedButton.icon(
            onPressed: _pickBackgroundImage,
            icon: const Icon(Icons.image),
            label: const Text('Select Background Image'),
          ),
        const SizedBox(height: 20),

        // Icon Pack
        _buildSectionTitle('Icon Pack'),
        const SizedBox(height: 10),
        if (_settings.iconPackPath != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _settings.iconPackPath!,
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _removeIconPack,
                    icon: const Icon(Icons.delete),
                    label: const Text('Remove Icon Pack'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_settings.iconMappings.isNotEmpty) ...[
                const Text(
                  'Icon Mappings:',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                ..._settings.iconMappings.entries.map((entry) {
                  return Card(
                    color: Colors.grey[800],
                    child: ListTile(
                      title: Text(
                        entry.key,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        entry.value,
                        style: TextStyle(color: Colors.grey[400], fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeIconMapping(entry.key),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => _showAddIconMappingDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Icon Mapping'),
                ),
              ] else
                ElevatedButton.icon(
                  onPressed: () => _showAddIconMappingDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Icon Mapping'),
                ),
            ],
          )
        else
          ElevatedButton.icon(
            onPressed: _pickIconPackDirectory,
            icon: const Icon(Icons.folder),
            label: const Text('Select Icon Pack Directory'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isWindowMode) {
      // Window mode - full screen widget
      return Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(20),
        color: Colors.grey[900],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Dock Settings',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    widget.onSave(_settings);
                  },
                ),
              ],
            ),
            const Divider(color: Colors.grey),
            Expanded(
              child: SingleChildScrollView(
                child: _buildSettingsContent(),
              ),
            ),
            const Divider(color: Colors.grey),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    widget.onSave(_settings);
                    if (widget.onRestart != null) {
                      widget.onRestart!();
                    }
                  },
                  child: const Text('Restart Dock'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(_settings);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Dialog mode
      return Dialog(
        backgroundColor: Colors.grey[900],
        child: Container(
          width: 600,
          height: 700,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dock Settings',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: Colors.grey),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildSettingsContent(),
                ),
              ),
              const Divider(color: Colors.grey),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () {
                      widget.onSave(_settings);
                      if (widget.onRestart != null) {
                        widget.onRestart!();
                      }
                      Navigator.of(context).pop();
                    },
                    child: const Text('Restart Dock'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      widget.onSave(_settings);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  void _showAddIconMappingDialog() {
    final appNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Add Icon Mapping', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: appNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'App Name',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                if (appNameController.text.isNotEmpty) {
                  await _pickIconForApp(appNameController.text);
                  if (mounted) Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.image),
              label: const Text('Select Icon'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

