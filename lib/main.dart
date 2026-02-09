// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async'; // Para usar Timer
import 'package:http/http.dart' as http; // Para peticiones HTTP
import 'package:intl/intl.dart';

// Constante de la API
const String kApiUrl = 'http://85.239.235.193:5000/api/status';
const String kInputApiUrl = 'http://85.239.235.193:5000/api/replicatorinput';

// Definición de la estructura de datos
class ProcessingData {
  final int packageCount;
  final String status;
  final DateTime generationDate;
  final DateTime processingDate;
  final String originNode;
  final String tableName;

  ProcessingData({
    required this.packageCount,
    required this.status,
    required this.generationDate,
    required this.processingDate,
    required this.originNode,
    required this.tableName,
  });

  factory ProcessingData.fromJson(Map<String, dynamic> json) {
    // Función de ayuda para parsear las fechas
    DateTime parseDate(String dateStr, {bool isProcessing = false}) {
      try {
        if (isProcessing) {
          // El formato es: "dd/MM/yyyy HH:mm:ss:SSS".
          // Se reconstruye la cadena a formato ISO 8601 modificado (YYYY-MM-DD HH:mm:ss.SSS)
          final parts = dateStr.split(' ');
          final datePart = parts[0];
          final timePart = parts[1];

          final day = datePart.substring(0, 2);
          final month = datePart.substring(3, 5);
          final year = datePart.substring(6, 10);

          final timeParts = timePart.split(':');
          final hour = timeParts[0];
          final minute = timeParts[1];
          final second = timeParts[2];
          final millisecond = timeParts[3];

          return DateTime.parse(
              '$year-$month-$day $hour:$minute:$second.$millisecond');
        } else {
          // Formato de generación: "YYYY/MM/DD HH:mm:ss.SSS"
          // Reemplazamos '/' por '-' y ' ' por 'T' para asegurar el parseo ISO 8601
          // Nota: El 'T' en replaceFirst no es necesario si el formato ya está en 'YYYY-MM-DD HH:MM:SS.mmm'
          return DateTime.parse(dateStr.replaceAll('/', '-'));
        }
      } catch (e) {
        // En caso de error de parseo, retorna la hora actual como fallback
        // Es importante revisar el formato de la API si esto ocurre
        debugPrint('Error parsing date: $dateStr. Error: $e');
        return DateTime.now();
      }
    }

    return ProcessingData(
      packageCount: json['cantidad_paquete'] as int,
      status: json['estado'] as String,
      generationDate: parseDate(json['fecha_generacion_paquete'] as String),
      processingDate:
          parseDate(json['fecha_procesamiento'] as String, isProcessing: true),
      originNode: json['nodo_origen'] as String,
      tableName: json['nombre_tabla'] as String,
    );
  }
}

// Constantes de estilo
const Color kBackgroundColor = Color(0xFF1E212D);
const Color kCardColor = Color(0xFF2B2F3C);
const Color kAccentColor = Color(0xFF8B8FFF); // Azul/Púrpura suave para acentos
const Color kSuccessColor = Color(0xFF4CAF50); // Verde para procesado
const Color kErrorColor = Color(0xFFEF5350); // Rojo para error
const Color kTextColor = Colors.white70;

void main() {
  runApp(const ProcessingDashboardApp());
}

class ProcessingDashboardApp extends StatelessWidget {
  const ProcessingDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBackgroundColor,
        cardColor: kCardColor,
        textTheme: Typography.whiteMountainView.copyWith(
          titleLarge: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
          titleMedium: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
          bodyMedium: const TextStyle(color: kTextColor),
          labelSmall: const TextStyle(color: kTextColor, fontSize: 12),
        ),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Estado para manejar la carga y los errores
  List<ProcessingData> data = [];
  bool isLoading = true;
  String? errorMessage;
  Timer? _timer;

  // Métricas
  int totalRecords = 0;
  int totalPackages = 0;
  int inputPackages = 0;
  Map<String, int> outputNodes = {};
  int errorCount = 0;
  int processedCount = 0;

  @override
  void initState() {
    super.initState();
    // Iniciar la carga de datos y el monitoreo
    startMonitoring();
  }

  @override
  void dispose() {
    // Es crucial cancelar el Timer cuando el Widget se destruye para evitar fugas de memoria
    _timer?.cancel();
    super.dispose();
  }

  // Función para obtener datos de la API
  Future<void> fetchData() async {
    // Solo mostrar el indicador de carga si es la primera vez que se obtienen datos
    setState(() {
      isLoading = data.isEmpty;
      errorMessage = null;
    });

    try {
      // Obtener datos del status
      final statusResponse = await http.get(Uri.parse(kApiUrl));

      if (statusResponse.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(statusResponse.body);

        final newData =
            jsonList.map((json) => ProcessingData.fromJson(json)).toList();

        // 2. Calcular las métricas con los nuevos datos
        int newTotalRecords = newData.length;
        // La función fold suma la cantidad de paquetes de todos los nodos
        int newTotalPackages =
            newData.fold<int>(0, (sum, item) => sum + item.packageCount);
        int newErrorCount =
            newData.where((item) => item.status == 'error').length;
        int newProcessedCount = newTotalRecords - newErrorCount;

        // Obtener datos de input packages
        int newInputPackages = 0;
        Map<String, int> newOutputNodes = {};
        try {
          final inputResponse = await http.get(Uri.parse(kInputApiUrl));
          if (inputResponse.statusCode == 200) {
            final inputData = json.decode(inputResponse.body);
            // Extraer datos de 'datos'
            if (inputData is Map && inputData.containsKey('datos')) {
              final datos = inputData['datos'];
              if (datos is Map) {
                datos.forEach((key, value) {
                  final k = key.toString();
                  if (k == 'replicator/input/') {
                    newInputPackages = value as int;
                  } else if (k.startsWith('replicator/output/')) {
                    newOutputNodes[k] = value as int;
                  }
                });
              }
            }
          }
        } catch (e) {
          // Si falla la API de input, continuar con 0
          debugPrint('Error obteniendo datos de input: $e');
        }

        // 3. Actualizar el estado
        if (mounted) {
          setState(() {
            data = newData;
            totalRecords = newTotalRecords;
            totalPackages = newTotalPackages;
            inputPackages = newInputPackages;
            outputNodes = newOutputNodes;
            errorCount = newErrorCount;
            processedCount = newProcessedCount;
            isLoading = false;
          });
        }
      } else {
        // Manejo de errores de respuesta HTTP (e.g., 404, 500)
        throw Exception(
            'Fallo al cargar datos de la API. Código: ${statusResponse.statusCode}');
      }
    } catch (e) {
      // Manejo de errores de conexión (e.g., red no disponible)
      if (mounted) {
        setState(() {
          errorMessage = 'Error de conexión: Verifica la URL o la red. $e';
          isLoading = false;
        });
      }
    }
  }

  // Configurar el temporizador para la actualización periódica cada 30 segundos
  void startMonitoring() {
    // Obtener los datos inmediatamente
    fetchData();

    // Configurar el timer para repetir la función cada 30 segundos
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      fetchData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Replicator Genex',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: kCardColor,
        elevation: 0,
        actions: [
          // Botón para refrescar manualmente
          IconButton(
            icon: const Icon(Icons.refresh, color: kAccentColor),
            onPressed: fetchData,
            tooltip: 'Refrescar datos',
          ),
          // Indicador visual de monitoreo activo
          const Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Icon(
              Icons.sensors_rounded,
              color: kSuccessColor,
              size: 20,
            ),
          )
        ],
      ),
      body: _buildBodyContent(context),
    );
  }

  // Construye el contenido principal (indicador de carga, error o dashboard)
  Widget _buildBodyContent(BuildContext context) {
    if (isLoading && data.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: kAccentColor));
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            errorMessage!,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: kErrorColor),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Título de la sección
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Text(
              'Resumen Procesamiento de Nodos',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontSize: 28, color: kAccentColor),
            ),
          ),

          // Fila de Tarjetas de Resumen (KPIs)
          LayoutBuilder(
            builder: (context, constraints) {
              // Diseño responsive: 4 columnas en ancho, 2 en estrecho
              final isWide = constraints.maxWidth > 600;
              final crossAxisCount = isWide ? 4 : 2;

              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: isWide ? 1.5 : 1.2,
                crossAxisSpacing: 16.0,
                mainAxisSpacing: 16.0,
                children: [
                  KpiCard(
                    title: 'Nodos Procesados',
                    value: processedCount.toString(),
                    icon: Icons.check_circle_outline,
                    color: kSuccessColor,
                  ),
                  KpiCard(
                    title: 'Nodos con Error',
                    value: errorCount.toString(),
                    icon: Icons.error_outline,
                    color: kErrorColor,
                  ),
                  KpiCard(
                    title: 'Paquetes Input',
                    // Usamos NumberFormat para mostrar el número con separador de miles
                    value: NumberFormat('#,##0').format(inputPackages),
                    icon: Icons.all_inbox_outlined,
                    color: const Color(0xFF64B5F6), // Azul claro
                  ),
                  // Tarjeta agrupada para Nodos Output
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              OutputNodesScreen(outputNodes: outputNodes),
                        ),
                      );
                    },
                    child: KpiCard(
                      title: 'Nodos Output',
                      value: outputNodes.length.toString(),
                      icon: Icons.hub,
                      color: const Color(0xFFAB47BC),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 40.0),

          // Título de la sección de Detalles
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Text(
              'Detalle de Transacciones Recientes',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontSize: 28, color: kAccentColor),
            ),
          ),

          // Lista de Detalles de Procesamiento
          ProcessingDetailList(data: data),
        ],
      ),
    );
  }
}

// Widget para las Tarjetas de Resumen (KPI)
class KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double? titleFontSize;

  const KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.titleFontSize,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: kCardColor,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Icono con fondo semitransparente
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const Spacer(),
            // Valor principal
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800,
              ),
            ),
            // Título/Descripción
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: kTextColor,
                    fontWeight: FontWeight.w500,
                    fontSize: titleFontSize ?? 14,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// Pantalla de detalle para los nodos de output
class OutputNodesScreen extends StatelessWidget {
  final Map<String, int> outputNodes;

  const OutputNodesScreen({required this.outputNodes, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle Nodos Output',
            style: TextStyle(color: Colors.white)),
        backgroundColor: kCardColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            final crossAxisCount = isWide ? 4 : 2;

            // Ordenamos por nombre
            final sortedEntries = outputNodes.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key));

            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: isWide ? 1.5 : 1.2,
                crossAxisSpacing: 16.0,
                mainAxisSpacing: 16.0,
              ),
              itemCount: sortedEntries.length,
              itemBuilder: (context, index) {
                final entry = sortedEntries[index];
                // Limpiar el nombre
                String name = entry.key.replaceFirst('replicator/output/', '');
                if (name.endsWith('/')) {
                  name = name.substring(0, name.length - 1);
                }
                final parts = name.split('/');
                final displayName = parts.isNotEmpty ? parts.last : name;

                return KpiCard(
                  title: displayName.replaceAll('_', ' ').toUpperCase(),
                  value: NumberFormat('#,##0').format(entry.value),
                  icon: Icons.outbox_rounded,
                  color: const Color(0xFFAB47BC),
                  titleFontSize: 11,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// Widget para la lista detallada de procesamiento
class ProcessingDetailList extends StatelessWidget {
  final List<ProcessingData> data;

  const ProcessingDetailList({required this.data, super.key});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kCardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No hay datos de nodos para mostrar. Verifique la conexión a la API.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    // Ordenar los datos por fecha de procesamiento (más reciente primero)
    final sortedData = List<ProcessingData>.from(data)
      ..sort((a, b) => b.processingDate.compareTo(a.processingDate));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calcular el ancho de cada tarjeta para que quepan 5 en la pantalla
        // Restamos un poco de espacio para el padding/separación
        // Si la pantalla es muy pequeña (móvil), mostramos menos (ej. 2)
        final itemsPerLine = constraints.maxWidth > 600 ? 5 : 2;
        final cardWidth = (constraints.maxWidth / itemsPerLine) - 16;

        return SizedBox(
          height: 200, // Altura fija para la lista horizontal
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sortedData.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final item = sortedData[index];
              final isError = item.status == 'error';
              final statusColor = isError ? kErrorColor : kSuccessColor;

              return SizedBox(
                width: cardWidth,
                child: Card(
                  color: kCardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isError
                                  ? Icons.cancel_outlined
                                  : Icons.check_circle_outline,
                              color: statusColor,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.originNode
                                    .toUpperCase()
                                    .replaceAll('_', ' '),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          'Tabla: ${item.tableName}',
                          style:
                              const TextStyle(color: kTextColor, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.packageCount} Paquetes',
                          style: const TextStyle(
                            color: kAccentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('HH:mm:ss').format(item.processingDate),
                          style:
                              const TextStyle(color: kTextColor, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
